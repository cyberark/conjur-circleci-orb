#!/usr/bin/env groovy
@Library('product-pipelines-shared-library') _

// Automated release, promotion and dependencies
properties([
  // Include the automated release parameters for the build
  release.addParams(),
  // Dependencies of the project that should trigger builds
  dependencies([])
])

// Performs release promotion.  No other stages will be run
if (params.MODE == 'PROMOTE') {
  release.promote(params.VERSION_TO_PROMOTE) { infrapool, sourceVersion, targetVersion, assetDirectory ->
    // Any assets from sourceVersion Github release are available in assetDirectory
    // Any version number updates from sourceVersion to targetVersion occur here
    // Any publishing of targetVersion artifacts occur here
    // Anything added to assetDirectory will be attached to the Github Release

    //Note: assetDirectory is on the infrapool agent, not the local Jenkins agent.
    // Build public orb for promotion
    infrapool.agentSh 'summon ./bin/build.sh public'
    infrapool.agentSh "summon ./bin/promote.sh ${assetDirectory} ${targetVersion} public"
  }
  release.copyEnterpriseRelease(params.VERSION_TO_PROMOTE)
  return
}

pipeline {
  agent { label 'conjur-enterprise-common-agent' }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  triggers {
    cron(getDailyCronString())
  }

  environment {
    // Sets the MODE to the specified or auto calculated value as appropriate
    MODE = release.canonicalizeMode()
  }

  stages {
    // Aborts any builds triggered by another project that would not include any changes
    stage("Skip build if triggering job didn't create a release") {
      when {
        expression {
          MODE == 'SKIP'
        }
      }
      steps {
        script {
          currentBuild.result = 'ABORTED'
          error('Aborting build because this build was triggered from upstream, but no release was built')
        }
      }
    }

    stage('Checkout Branches - Main Agent') {
      steps {
        script {
          checkoutBranches(null)
          // Update secrets-manager-integration-environment-bootstrap submodule to the latest main branch
          // This is needed as its hard to update the submodule pointer
          // as it uses https:// not ssh as transport.
          withCredentials([gitUsernamePassword(credentialsId: 'jenkins_ci_token')]) {
            dir('secrets-manager-integration-environment-bootstrap') {
              sh 'git config http."https://github.cyberng.com/".sslVerify false'
              sh 'git fetch origin; git reset --hard origin/main'
            }
          }
        }
      }
    }

    stage('Get InfraPool ExecutorV2 Agent(s)') {
      steps {
        script {
          // Request ExecutorV2 agents for 1 hour
          infrapool = getInfraPoolAgent.connected(type: 'ExecutorV2', quantity: 1, duration: 1)[0]
        }
      }
    }

    // Generates a VERSION file based on the current build number and latest version in CHANGELOG.md
    stage('Validate Changelog and set version') {
      steps {
        script {
          updateVersion(infrapool, 'CHANGELOG.md', "${BUILD_NUMBER}")
        }
      }
    }
    stage('Unit Tests & Coverage') {
      steps {
        script {
          infrapool.agentSh './bin/unit_test_coverage.sh'
          infrapool.agentStash name: 'junit-xml', includes: 'output/*.xml'
        }
      }
      post {
        always {
          unstash 'junit-xml'
          junit 'output/junit.xml'
          cobertura autoUpdateHealth: false, autoUpdateStability: false, coberturaReportFile: 'output/coverage.xml', conditionalCoverageTargets: '30, 0, 0', failUnhealthy: false, failUnstable: false, lineCoverageTargets: '30, 0, 0', maxNumberOfBuilds: 0, methodCoverageTargets: '30, 0, 0', onlyStable: false, sourceEncoding: 'ASCII', zoomCoverageChart: false
          codacy action: 'reportCoverage', filePath: 'output/coverage.xml'
        }
      }
    }
    stage('Build artifacts') {
      steps {
        script {
          infrapool.agentSh 'summon ./bin/build.sh private'
        }
      }
    }
    stage('Publish Private CircleCI Orb') {
      steps {
        script {
          infrapool.agentSh "summon ./bin/promote.sh dist ${BUILD_NUMBER} private"
        }
      }
    }

    stage('Create Conjur Cloud Tenant') {
          steps {
            script {
              TENANT = getConjurCloudTenant()
            }
          }
    }
        stage('Authenticate to Conjur Cloud Tenant') {
          steps {
            script {
              def id_token = getConjurCloudTenant.tokens(
                infrapool: infrapool,
                identity_url: "${TENANT.identity_information.idaptive_tenant_fqdn}",
                username: "${TENANT.login_name}"
              )

              def conj_token = getConjurCloudTenant.tokens(
                infrapool: infrapool,
                conjur_url: "${TENANT.conjur_cloud_url}",
                identity_token: "${id_token}"
                )

              env.conj_token = conj_token
            }
          }
        }
        stage('Run tests against Conjur Cloud Tenant') {
          environment {
            INFRAPOOL_CONJUR_APPLIANCE_URL = "${TENANT.conjur_cloud_url}"
            INFRAPOOL_CONJUR_AUTHN_LOGIN = "${TENANT.login_name}"
            INFRAPOOL_CONJUR_AUTHN_TOKEN = "${env.conj_token}"
            INFRAPOOL_TEST_CLOUD = true
          }
          steps {
            script {
              infrapool.agentSh 'summon ./bin/integration_test_coverage.sh saas circleci-jwt'
            }
          }
        }
        stage('Retrieve Conjur Edge Token') {
          steps {
            script {
              def edge_token = getConjurCloudTenant.tokens(
                infrapool: infrapool,
                conjur_url: "${TENANT.conjur_cloud_url}",
                edge_name: "${TENANT.conjur_edge_name}",
                conjur_token: "${env.conj_token}"
              )
              env.edge_token = edge_token
            }
          }
        }
        stage('Run tests against Conjur Cloud Edge') {
          environment {
            INFRAPOOL_CONJUR_APPLIANCE_URL = "${TENANT.conjur_cloud_url}"
            INFRAPOOL_CONJUR_AUTHN_LOGIN = "${TENANT.login_name}"
            INFRAPOOL_CONJUR_AUTHN_TOKEN = "${env.edge_token}"
            INFRAPOOL_TEST_CLOUD = true
            CONJUR_CLOUD_URL = "${TENANT.conjur_cloud_url}"
            TOKEN = "${env.edge_token}"
            EDGE_NAME = 'edge-test-integration'
            COMMON_NAME = 'edge-test-integration'
            SUBJECT_ALT_NAMES = 'edge-test-integration'
          }
          steps {
            script {
              echo "INFRAPOOL_CONJUR_AUTHN_TOKEN: ${env.INFRAPOOL_CONJUR_AUTHN_TOKEN}"
              echo "INFRAPOOL_CONJUR_AUTHN_TOKEN2: ${INFRAPOOL_CONJUR_AUTHN_TOKEN}"
              echo "INFRAPOOL_CONJUR_AUTHN_TOKEN2: ${INFRAPOOL_CONJUR_APPLIANCE_URL}"
              infrapool.agentSh 'summon ./bin/integration_test_coverage.sh edge circleci-jwt'
            }
          }
        }

    stage('Run tests against Conjur OSS') {
      steps {
        script {
          infrapool.agentSh 'summon ./bin/integration_test_coverage.sh oss circleci-jwt'
          infrapool.agentStash name: 'junit-xml', includes: 'output-integration/*.xml'
        }
      }
    }
    stage('Run tests against Conjur Enterprise') {
      steps {
        script {
          infrapool.agentSh 'summon ./bin/integration_test_coverage.sh enterprise circleci-jwt'
          infrapool.agentStash name: 'junit-xml', includes: 'output-integration/*.xml'
        }
      }
    }
    stage('Stage running on Atlantis Jenkins Agent Container') {
      steps {
        sh 'scripts/in-container.sh'
      }
    }
    stage('Stage on AWS Instance') {
      steps {
        script {
          // Run script from repo on an AWS instance managed by infrapool
          infrapool.agentSh 'scripts/on-instance.sh'
        }
      }
    }

    stage('Release') {
      when {
        expression {
          MODE == 'RELEASE'
        }
      }

      steps {
        script {
          release(infrapool, { billOfMaterialsDirectory, assetDirectory ->
            /* Publish release artifacts to all the appropriate locations
               Copy any artifacts to assetDirectory on the infrapool node
               to attach them to the Github release.

               If your assets are on the infrapool node in the target
               directory, use a copy like this:
                  infrapool.agentSh "cp target/* ${assetDirectory}"
               Note That this will fail if there are no assets, add :||
               if you want the release to succeed with no assets.

               If your assets are in target on the main Jenkins agent, use:
                 infrapool.agentPut(from: 'target/', to: assetDirectory)
            */
            infrapool.agentSh "cp -r dist/*.yml  dist/*_SHA256SUMS ${assetDirectory}"
          })
        }
      }
    }
  }

  post {
    always {
      releaseInfraPoolAgent()
    }
  }
}

// Extracted into a function as it must be run on both nodes used
// by this pipeline
// Checkout branches on the atlantis agent and the infrapool agent
void checkoutBranches(infrapool) {
  if (infrapool != null) {
    fetch = ''
    // Cant fetch from github enterprise on infrapool agent
    // Checkout the correct branch on the infrapool agent
    infrapool.agentSh(_getCheckoutScript(fetch))
  } else {
    fetch = "git fetch origin; git fetch origin 'refs/pull/*:refs/pull/*'||:"
    // Checkout the correct branch on the atlantis agent
    withCredentials([gitUsernamePassword(credentialsId: 'jenkins_ci_token')]) {
      sh(_getCheckoutScript(fetch))
    }
  }
}

String _getCheckoutScript(fetch) {
  return """#!/usr/bin/env bash
    set -xeuo pipefail
    # Initialize secrets-manager-integration-environment-bootstrap submodule if it doesn't exist
    if [[ ! -d "secrets-manager-integration-environment-bootstrap/.git" ]]; then
      git submodule update --init secrets-manager-integration-environment-bootstrap
    fi
    # Update secrets-manager-integration-environment-bootstrap submodule from root directory
    git -C secrets-manager-integration-environment-bootstrap clean -dfx
    git -C secrets-manager-integration-environment-bootstrap reset --hard
    if [[ -n "${fetch}" ]]; then
      git -C secrets-manager-integration-environment-bootstrap fetch origin
      if [[ "${fetch}" == *"refs/pull"* ]]; then
        git -C secrets-manager-integration-environment-bootstrap fetch origin 'refs/pull/*:refs/pull/*' || :
      fi
    fi
    git -C secrets-manager-integration-environment-bootstrap reset --hard "origin/main"
  """
}
