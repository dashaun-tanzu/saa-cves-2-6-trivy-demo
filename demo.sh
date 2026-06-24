#!/usr/bin/env bash

DEMO_START=$(date +%s)

TEMP_DIR="upgrade-example"

# Java version configuration — sourced from .sdkmanrc
JAVA8_VERSION=$(grep '^java=8' "$(dirname "$0")/.sdkmanrc" | cut -d'=' -f2)
JAVA21_VERSION=$(grep '^java=21' "$(dirname "$0")/.sdkmanrc" | cut -d'=' -f2)
JAVA21_HOME="${SDKMAN_DIR:-$HOME/.sdkman}/candidates/java/$JAVA21_VERSION"

export SPRING_ADVISOR_MAPPING_CUSTOM_0_GIT_URI="https://github.com/dashaun-tanzu/advisor-mappings.git"
export SPRING_ADVISOR_MAPPING_CUSTOM_0_GIT_PATH="mappings/"
export SPRING_ADVISOR_MAPPING_CUSTOM_0_MERGE_STRATEGY=override

check_dependency() {
  local cmd=$1
  local install_msg=$2

  if ! command -v "$cmd" &> /dev/null; then
    echo "$cmd not found. $install_msg"
    return 1
  fi
  return 0
}

check_dependencies() {
  local missing_deps=()

  check_dependency "vendir" "Please install vendir first." || missing_deps+=("vendir")
  check_dependency "http" "Please install httpie first." || missing_deps+=("httpie")
  check_dependency "bc" "Please install bc first." || missing_deps+=("bc")
  check_dependency "git" "Please install git first." || missing_deps+=("git")
  check_dependency "jq" "Please install jq first." || missing_deps+=("jq")
  check_dependency "tar" "Please install tar first." || missing_deps+=("tar")
  check_dependency "trivy" "Please install trivy first (brew install trivy)." || missing_deps+=("trivy")

  if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "Missing dependencies: ${missing_deps[*]}"
    exit 1
  fi

  echo "All dependencies found."
}

check_env_vars() {
  local missing_vars=()

  [[ -z "${ADVISOR_VERSION}" ]] && missing_vars+=("ADVISOR_VERSION")

  if [ ${#missing_vars[@]} -gt 0 ]; then
    echo "Missing required environment variables: ${missing_vars[*]}"
    exit 1
  fi

  echo "All required environment variables found."
}

check_dependencies
check_env_vars

[[ ! -d "./vendir/demo-magic" ]] && vendir sync
. ./vendir/demo-magic/demo-magic.sh
export TYPE_SPEED=100
export DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"
export PROMPT_TIMEOUT=5


function cleanUp {
	local npid=""

  npid=$(pgrep java)

 	if [ "$npid" != "" ]
		then

  		displayMessage "*** Stopping Any Previous Existing SpringBoot Apps..."

			while [ "$npid" != "" ]
			do
				echo "***KILLING OFF The Following: $npid..."
		  	pei "kill -9 $npid"
				npid=$(pgrep java)
			done

	fi
}

function talkingPoint() {
  wait
  clear
}

function initSDKman() {
  local sdkman_init
  sdkman_init="${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh"
  if [[ -f "$sdkman_init" ]]; then
    # shellcheck disable=SC1090
    source "$sdkman_init"
  else
    echo "SDKMAN not found. Please install SDKMAN first."
    exit 1
  fi
}

function init {
  rm -rf "$TEMP_DIR"
  mkdir "$TEMP_DIR"
  cd "$TEMP_DIR" || exit
  clear
}

function useJava8 {
  displayMessage "Use Java 8 for Spring Boot 2.6 baseline"
  pei "sdk use java $JAVA8_VERSION"
  pei "java -version"
}

function useJava21 {
  displayMessage "Switch to Java 21 for Spring Boot 4"
  pei "sdk use java $JAVA21_VERSION"
  pei "java -version"
}

function cloneApp {
  displayMessage "Clone a Spring Boot 2.6 application"
  pei "git clone https://github.com/dashaun/hello-spring-boot-2-6.git ./"
}

function springBootBuild {
  displayMessage "Build the Spring Boot application"
  pei "./mvnw -q clean package -DskipTests"
}

function springBootStart {
  displayMessage "Start the Spring Boot application, Wait For It...."
  pei "./mvnw -q package spring-boot:start -Dfork=true -DskipTests 2>&1 | tee '$1' &"
}

function springBootStop {
  displayMessage "Stop the Spring Boot application"
  pei "./mvnw spring-boot:stop -Dspring-boot.stop.fork -Dfork=true"
}

function validateApp {
  displayMessage "Check application health"
  pei "http :8080/actuator/health 2>/dev/null"
}

function showMemoryUsage {
  local pid=$1
  local log_file=$2
  local rss
  rss=$(ps -o rss= "$pid" | tail -n1)
  local mem_usage
  mem_usage=$(bc <<< "scale=1; ${rss}/1024")
  echo "The process was using ${mem_usage} megabytes"
  echo "${mem_usage}" >> "$log_file"
}

function startCVECheckBackground {
  local log_file=$1

  # Extract the CycloneDX SBOM that advisor wrote into build-config.json to a path
  # outside target/, so it survives the upcoming `mvn clean` in springBootBuild.
  jq '.sbom' target/.advisor/build-config.json > sbom-cdx.json

  displayMessage "Scanning advisor's CycloneDX SBOM with Trivy in the background..."
  displayMessage "trivy sbom --quiet --format json --scanners vuln sbom-cdx.json"
  trivy sbom --quiet --format json --scanners vuln sbom-cdx.json > trivy-report.json 2> trivy-check.log &
  CVE_CHECK_PID=$!
  disown $CVE_CHECK_PID
}

function collectCVECount {
  local log_file=$1
  displayMessage "Collecting Trivy results..."
  wait "$CVE_CHECK_PID"
  local cve_count
  cve_count=$(jq '[.Results[]?.Vulnerabilities[]?] | length' trivy-report.json)
  echo "Found ${cve_count} known CVEs"
  echo "${cve_count}" > "$log_file"
}

function advisorArtifactId {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "$os" in
    Darwin)
      if [[ "$arch" == "arm64" ]]; then
        echo "application-advisor-cli-macos-arm64"
      else
        echo "application-advisor-cli-macos"
      fi
      ;;
    Linux)
      echo "application-advisor-cli-linux"
      ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
      echo "application-advisor-cli-windows"
      ;;
    *)
      echo "Unsupported OS: $os" >&2
      return 1
      ;;
  esac
}

function downloadAdvisor {
  local artifact tar_file
  artifact=$(advisorArtifactId) || exit 1
  tar_file="${HOME}/.m2/repository/com/vmware/tanzu/spring/${artifact}/${ADVISOR_VERSION}/${artifact}-${ADVISOR_VERSION}.tar"

  displayMessage "Download Spring Application Advisor CLI ${ADVISOR_VERSION} (${artifact})"
  pei "mvn -q dependency:get -Dartifact=com.vmware.tanzu.spring:${artifact}:${ADVISOR_VERSION}:tar -Dtransitive=false"
  pei "tar -xf '${tar_file}' -C ."
  pei "./cli-binary/advisor --version"
}

function advisorBuildConfig {
  displayMessage "Capture some metadata about the application with Advisor"
  pei "./cli-binary/advisor build-config get"
}

function captureSBOMCount {
  local log_file=$1
  local sbom_count
  sbom_count=$(cat target/.advisor/build-config.json | jq '.sbom.components | length')
  echo "SBOM component count: ${sbom_count}"
  echo "${sbom_count}" > "$log_file"
}

function showBuildConfigKeys {
  displayMessage "Some interesting information from that step:"
  pei "cat target/.advisor/build-config.json | jq 'keys'"
  echo "^^^ The top level elements in the build-config.json file"
}

function showBuildConfigGitMetadata {
  pei "cat target/.advisor/build-config.json | jq '.\"git-metadata\"'"
  echo "^^^ Information about the git repository"
}

function showBuildConfigSBOMint {
  displayMessage "Some interesting information from that step:"
  pei "cat target/.advisor/build-config.json | jq '.sbom.components | length'"
  echo "^^^ That's the number of components included in the SBOM"
}

function showBuildConfigSubmodules {
  pei "cat target/.advisor/build-config.json | jq '.submodules'"
  echo "^^^ The Maven coordinates (groupId:artifactId) of the artifact(s)"
}

function showBuildConfigTools {
  pei "cat target/.advisor/build-config.json | jq '.tools'"
  echo "^^^ The tools and versions being used"
}

function advisorUpgradePlanGet {
  displayMessage "How hard could it be to upgrade? Let's get a plan!"
  pei "./cli-binary/advisor upgrade-plan get"
}

function advisorUpgradePlanApplySquash {
  displayMessage "Do all the upgrades!"
  pei "./cli-binary/advisor upgrade-plan apply --squash 10"
}

function displayMessage() {
  echo "#### $1"
  echo ""
}

function startupTime() {
  echo "$(sed -nE 's/.* in ([0-9]+\.[0-9]+) seconds.*/\1/p' < $1)"
}

function statsSoFarTableColored {
  displayMessage "Comparison of memory usage, startup times, CVEs, and dependencies"
  echo ""

  local WHITE='\033[1;37m'
  local GREEN='\033[1;32m'
  local BLUE='\033[1;34m'
  local NC='\033[0m'

  printf "${WHITE}%-35s %-25s %-10s %-10s %-15s %s${NC}\n" "Configuration" "Startup Time (seconds)" "Deps" "CVEs" "(MB) Used" "(MB) Savings"
  echo -e "${WHITE}--------------------------------------------------------------------------------------------------------------${NC}"

  MEM1=$(cat java8with2.6.log2)
  START1=$(startupTime 'java8with2.6.log')
  CVE1=$(cat java8with2.6.cves)
  DEPS1=$(cat java8with2.6.deps)
  printf "${RED}%-35s %-25s %-10s %-10s %-15s %s${NC}\n" "Spring Boot 2.6 with Java 8" "$START1" "$DEPS1" "$CVE1" "$MEM1" "-"

  MEM2=$(cat java21with4.0.log2)
  PERC2=$([ -n "$MEM2" ] && [ -n "$MEM1" ] && bc <<< "scale=2; 100 - ${MEM2}/${MEM1}*100" || echo "N/A")
  START2=$(startupTime 'java21with4.0.log')
  PERCSTART2=$([ -n "$START2" ] && [ -n "$START1" ] && bc <<< "scale=2; 100 - ${START2}/${START1}*100" || echo "N/A")
  CVE2=$(cat java21with4.0.cves)
  DEPS2=$(cat java21with4.0.deps)
  printf "${GREEN}%-35s %-25s %-10s %-10s %-15s %s ${NC}\n" "Spring Boot 4.0 with Java 21" "$START2 ($PERCSTART2% faster)" "$DEPS2" "$CVE2" "$MEM2" "$PERC2%"

  echo -e "${WHITE}--------------------------------------------------------------------------------------------------------------${NC}"
  DEMO_STOP=$(date +%s)
  DEMO_ELAPSED=$((DEMO_STOP - DEMO_START))
  echo ""
  echo ""
  echo -e "${BLUE}Demo elapsed time: ${DEMO_ELAPSED} seconds${NC}"
}

# Main execution flow

cleanUp
initSDKman
init
useJava8
talkingPoint
cloneApp
talkingPoint
downloadAdvisor
talkingPoint
advisorBuildConfig
talkingPoint
captureSBOMCount java8with2.6.deps
talkingPoint
showBuildConfigKeys
talkingPoint
showBuildConfigGitMetadata
talkingPoint
showBuildConfigSBOMint
talkingPoint
showBuildConfigSubmodules
talkingPoint
showBuildConfigTools
talkingPoint
startCVECheckBackground java8with2.6.cves
talkingPoint
springBootBuild
talkingPoint
springBootStart java8with2.6.log
talkingPoint
validateApp
talkingPoint
showMemoryUsage "$(jps | grep 'HelloSpringApplication' | cut -d ' ' -f 1)" java8with2.6.log2
talkingPoint
springBootStop
talkingPoint
collectCVECount java8with2.6.cves
talkingPoint
advisorUpgradePlanGet
talkingPoint
useJava21
talkingPoint
advisorUpgradePlanApplySquash
talkingPoint
advisorBuildConfig
talkingPoint
captureSBOMCount java21with4.0.deps
talkingPoint
startCVECheckBackground java21with4.0.cves
talkingPoint
springBootBuild
talkingPoint
springBootStart java21with4.0.log
talkingPoint
validateApp
talkingPoint
showMemoryUsage "$(jps | grep 'HelloSpringApplication' | cut -d ' ' -f 1)" java21with4.0.log2
talkingPoint
springBootStop
talkingPoint
collectCVECount java21with4.0.cves
talkingPoint
statsSoFarTableColored
