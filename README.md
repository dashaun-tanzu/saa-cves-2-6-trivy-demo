# Spring Application Advisor + Trivy Upgrade Example

## Description

This interactive demo showcases the power of Spring Application Advisor (SAA) by automatically upgrading a Spring Boot application from version 2.6 to 4.0. CVE counts are produced by scanning the built JAR with the [Trivy](https://github.com/aquasecurity/trivy) CLI.

### What the Demo Does

1. **Environment Setup**: Configures Java 8 and Java 21 environments using SDKMAN
2. **Baseline Measurement**: Clones and runs a Spring Boot 2.6 application with Java 8, measuring:
   - Startup time
   - Memory usage
   - Known CVEs (via `trivy sbom` against the CycloneDX SBOM that `advisor build-config get` produces, run in the background during build/app startup)
3. **Application Analysis**: Uses Spring Application Advisor to analyze the existing application, capturing:
   - Build configuration metadata
   - Software Bill of Materials (SBOM) with component/dependency inventory
   - Git repository information
   - Tool versions
4. **Automated Upgrade**: Generates and applies an upgrade plan that transforms the application to Spring Boot 4.0
5. **Post-Upgrade Analysis**: Runs `advisor build-config get` again after the upgrade to capture the updated SBOM
6. **Performance Validation**: Runs the upgraded application with Java 21 and measures the same metrics
7. **Results Comparison**: Displays a side-by-side table showing:
   - Startup time (with % improvement)
   - Dependency count (from SBOM)
   - Known CVE count (from Trivy)
   - Memory usage
   - Memory savings (%)

### Key Benefits Demonstrated

- **Zero Manual Effort**: Complete upgrade from Spring Boot 2.6 → 4.0 with no manual code changes
- **Performance Gains**: Typically shows improvements in startup speed and memory efficiency
- **Security Posture**: Demonstrates CVE reduction achieved by upgrading to a modern, supported version
- **Dependency Insight**: SBOM comparison shows how the dependency footprint changes after upgrade
- **Modern Java Features**: Leverages Java 21 optimizations and Spring Boot 4.x enhancements

## Prerequisites

- [Spring Application Advisor](https://enterprise.spring.io/spring-application-advisor)
  > Spring Enterprise Repository Access required
- [SDKMan](https://sdkman.io/install)
  > i.e. `curl -s "https://get.sdkman.io" | bash`
- [Trivy](https://github.com/aquasecurity/trivy)
  > i.e. `brew install trivy`
- [Httpie](https://httpie.io/) needs to be in the path
  > i.e. `brew install httpie`
- [jq](https://jqlang.github.io/jq/) needs to be in the path
  > i.e. `brew install jq`
- bc, pv, zip, unzip, gcc, zlib1g-dev
  > i.e. `sudo apt install bc pv zip unzip gcc zlib1g-dev -y`
- [Vendir](https://carvel.dev/vendir/)
  > i.e. `brew tap carvel-dev/carvel && brew install vendir`

## Required Environment Variables

```bash
export ADVISOR_VERSION=<advisor-cli-version>
```

- **ADVISOR_VERSION**: Version of the Spring Application Advisor CLI to download (e.g., `1.5.7`)

Trivy uses its own bundled vulnerability database and does not require API keys or credentials.

## Quick Start

```bash
./demo.sh
```

## Recording the Demo

Generate `demo.cast` with asciinema:

```bash
asciinema rec demo.cast --overwrite --cols 200 --rows 50 -c ./demo.sh
```

Convert to `demo.gif` with agg:

```bash
agg --speed 2 --no-loop demo.cast demo.gif
```

## Attributions
- [Demo Magic](https://github.com/paxtonhare/demo-magic) is pulled via `vendir sync` (skipped if already present)
- [Trivy](https://github.com/aquasecurity/trivy) by Aqua Security
