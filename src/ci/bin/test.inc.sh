#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# A set of common functions for use in other scripts.
#
# Functions:
#
#   - cromwell::build::*
#     Functions for use in other scripts
#
#   - cromwell::private::*
#     Functions for use only within this file by cromwell::build::* functions
#
# Special Variables
#
#   - CROMWELL_BUILD_*
#     Variables for use in other scripts.
#
#   - crmdbg
#     Quick debug scripts. Example: `crmdbg=y src/ci/bin/testCentaurLocal.sh`
#
#   - crmcit
#     Simulate a centaur integration test build. Example: `crmcit=y src/ci/bin/testCentaurPapiV2beta.sh`
#
#   - crmddm
#     Use "Docker Desktop for Mac" DNS names instead of `localhost`.
#     Example: `crmddm=y src/ci/bin/testCentaurHoricromtalPapiV2alpha1.sh`
#     More info: https://docs.docker.com/docker-for-mac/networking/#i-want-to-connect-from-a-container-to-a-service-on-the-host

cromwell::private::check_debug() {
    # shellcheck disable=SC2154
    if [[ -n "${crmdbg:+set}" ]]; then
        set -o xtrace
    fi

    # shellcheck disable=SC2154
    if [[ -n "${crmcit:+set}" ]]; then
        CROMWELL_BUILD_CENTAUR_TYPE="integration"
    fi

    # shellcheck disable=SC2154
    if [[ -n "${crmddm:+set}" ]]; then
        CROMWELL_BUILD_DOCKER_LOCALHOST="host.docker.internal"
    fi
}

cromwell::private::check_if_files_changed() {
    local files_changed
    local regex_changed
    files_changed="${1:?check_if_files_changed called without the files}"
    regex_changed="${2:?check_if_files_changed called without the regex}"
    shift 2

    if grep -E -q --invert-match "${regex_changed}" <<< "${files_changed}"; then
        echo false
    else
        echo true
    fi
}

cromwell::private::get_github_pr_json() {
    local github_pr_repository
    local github_pr_number
    github_pr_repository="${1:?get_github_pr_json called without the github_pr_repository}"
    github_pr_number="${2:?get_github_pr_json called without the github_pr_number}"
    shift 2

    curl \
        --location \
        --silent \
        "https://api.github.com/repos/${github_pr_repository}/pulls/${github_pr_number}" \
        || echo '{}'
}

# Exports environment variables used for scripts.
cromwell::private::create_build_variables() {
    CROMWELL_BUILD_PROVIDER_TRAVIS="travis"
    CROMWELL_BUILD_PROVIDER_GITHUB="github"
    CROMWELL_BUILD_PROVIDER_CIRCLE="circle"
    CROMWELL_BUILD_PROVIDER_GOOGLE="google"
    CROMWELL_BUILD_PROVIDER_JENKINS="jenkins"
    CROMWELL_BUILD_PROVIDER_CIRCLE="circle"
    CROMWELL_BUILD_PROVIDER_UNKNOWN="unknown"

    if [[ "${TRAVIS-false}" == "true" ]]; then
        CROMWELL_BUILD_PROVIDER="${CROMWELL_BUILD_PROVIDER_TRAVIS}"
    elif [[ "${GITHUB_ACTIONS-false}" == "true" ]]; then
        CROMWELL_BUILD_PROVIDER="${CROMWELL_BUILD_PROVIDER_GITHUB}"
    elif [[ "${CLOUD_BUILD-false}" == "true" ]]; then
        CROMWELL_BUILD_PROVIDER="${CROMWELL_BUILD_PROVIDER_GOOGLE}"
    elif [[ "${CIRCLECI-false}" == "true" ]]; then
        CROMWELL_BUILD_PROVIDER="${CROMWELL_BUILD_PROVIDER_CIRCLE}"
    elif [[ "${JENKINS-false}" == "true" ]]; then
        CROMWELL_BUILD_PROVIDER="${CROMWELL_BUILD_PROVIDER_JENKINS}"
    elif [[ "${CIRCLECI-false}" == "true" ]]; then
        CROMWELL_BUILD_PROVIDER="${CROMWELL_BUILD_PROVIDER_CIRCLE}"
    else
        CROMWELL_BUILD_PROVIDER="${CROMWELL_BUILD_PROVIDER_UNKNOWN}"
    fi

    # simplified from https://stackoverflow.com/a/18434831/3320205
    CROMWELL_BUILD_OS_DARWIN="darwin";
    CROMWELL_BUILD_OS_LINUX="linux";
    case "${OSTYPE-unknown}" in
        darwin*)  CROMWELL_BUILD_OS="${CROMWELL_BUILD_OS_DARWIN}" ;;
        linux*)   CROMWELL_BUILD_OS="${CROMWELL_BUILD_OS_LINUX}" ;;
        *)        CROMWELL_BUILD_OS="unknown_os" ;;
    esac

    CROMWELL_BUILD_HOME_DIRECTORY="${HOME}"
    CROMWELL_BUILD_ROOT_DIRECTORY="$(pwd)"
    CROMWELL_BUILD_LOG_DIRECTORY="${CROMWELL_BUILD_ROOT_DIRECTORY}/target/ci/logs"
    CROMWELL_BUILD_CROMWELL_LOG="${CROMWELL_BUILD_LOG_DIRECTORY}/cromwell.log"

    CROMWELL_BUILD_DOCKER_DIRECTORY="${CROMWELL_BUILD_ROOT_DIRECTORY}/src/ci/docker-compose"
    CROMWELL_BUILD_SCRIPTS_DIRECTORY="${CROMWELL_BUILD_ROOT_DIRECTORY}/src/ci/bin"
    CROMWELL_BUILD_RESOURCES_SOURCES="${CROMWELL_BUILD_ROOT_DIRECTORY}/src/ci/resources"
    CROMWELL_BUILD_RESOURCES_DIRECTORY="${CROMWELL_BUILD_ROOT_DIRECTORY}/target/ci/resources"

    CROMWELL_BUILD_GIT_SECRETS_DIRECTORY="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/git-secrets"
    CROMWELL_BUILD_GIT_SECRETS_COMMIT="ad82d68ee924906a0401dfd48de5057731a9bc84"
    CROMWELL_BUILD_WAIT_FOR_IT_FILENAME="wait-for-it.sh"
    CROMWELL_BUILD_WAIT_FOR_IT_BRANCH="db049716e42767d39961e95dd9696103dca813f1"
    CROMWELL_BUILD_WAIT_FOR_IT_URL="https://raw.githubusercontent.com/vishnubob/wait-for-it/${CROMWELL_BUILD_WAIT_FOR_IT_BRANCH}/${CROMWELL_BUILD_WAIT_FOR_IT_FILENAME}"
    CROMWELL_BUILD_WAIT_FOR_IT_SCRIPT="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/${CROMWELL_BUILD_WAIT_FOR_IT_FILENAME}"
    CROMWELL_BUILD_VAULT_ZIP="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/vault.zip"
    CROMWELL_BUILD_VAULT_EXECUTABLE="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/vault"
    CROMWELL_BUILD_EXIT_FUNCTIONS="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/cromwell_build_exit_functions.$$"

    if [[ -n "${VIRTUAL_ENV:+set}" ]]; then
        CROMWELL_BUILD_IS_VIRTUAL_ENV=true
    else
        CROMWELL_BUILD_IS_VIRTUAL_ENV=false
    fi

    CROMWELL_BUILD_CURRENT_VERSION_NUMBER="$( \
        grep 'val cromwellVersion' "${CROMWELL_BUILD_ROOT_DIRECTORY}/project/Version.scala" \
        | awk -F \" '{print $2}' \
        )"

    if git merge-base --is-ancestor "${CROMWELL_BUILD_CURRENT_VERSION_NUMBER}" HEAD 2>/dev/null; then
        CROMWELL_BUILD_IS_HOTFIX=true
    else
        CROMWELL_BUILD_IS_HOTFIX=false
    fi

    if [[ "${CROMWELL_BUILD_IS_HOTFIX}" == "true" ]]; then
        CROMWELL_BUILD_PRIOR_VERSION_NUMBER=${CROMWELL_BUILD_CURRENT_VERSION_NUMBER}
    else
        CROMWELL_BUILD_PRIOR_VERSION_NUMBER=$((CROMWELL_BUILD_CURRENT_VERSION_NUMBER - 1))
    fi

    local git_revision
    if git_revision="$(git rev-parse --short=7 HEAD 2>/dev/null)"; then
        CROMWELL_BUILD_GIT_HASH_SUFFIX="g${git_revision}"
    else
        CROMWELL_BUILD_GIT_HASH_SUFFIX="gUNKNOWN"
    fi

    local github_pr_repository
    local github_pr_number

    github_pr_repository=""
    github_pr_number=""

    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_TRAVIS}")
            CROMWELL_BUILD_IS_CI=true
            CROMWELL_BUILD_TYPE="${BUILD_TYPE}"
            CROMWELL_BUILD_NUMBER="${TRAVIS_JOB_NUMBER}"
            CROMWELL_BUILD_URL="https://travis-ci.com/${TRAVIS_REPO_SLUG}/jobs/${TRAVIS_JOB_ID}"
            CROMWELL_BUILD_GIT_USER_EMAIL="travis@travis-ci.com"
            CROMWELL_BUILD_GIT_USER_NAME="Travis CI"
            CROMWELL_BUILD_HEARTBEAT_PATTERN="…"
            CROMWELL_BUILD_GENERATE_COVERAGE=true

            CROMWELL_BUILD_EVENT="${TRAVIS_EVENT_TYPE}"
            CROMWELL_BUILD_IS_SECURE="${TRAVIS_SECURE_ENV_VARS}"
            CROMWELL_BUILD_BRANCH="${TRAVIS_PULL_REQUEST_BRANCH:-${TRAVIS_BRANCH}}"
            CROMWELL_BUILD_TAG="${TRAVIS_TAG}"

            if [[ "${TRAVIS_PULL_REQUEST}" != "false" ]]; then
                github_pr_repository="${TRAVIS_REPO_SLUG}"
                github_pr_number="${TRAVIS_PULL_REQUEST}"
            fi
            ;;
        "${CROMWELL_BUILD_PROVIDER_GITHUB}")
            CROMWELL_BUILD_IS_CI=true
            CROMWELL_BUILD_TYPE="${BUILD_TYPE}"
            CROMWELL_BUILD_NUMBER="${GITHUB_RUN_NUMBER}.${BUILD_NAME}"
            CROMWELL_BUILD_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
            CROMWELL_BUILD_GIT_USER_EMAIL="github-actions@github.com"
            CROMWELL_BUILD_GIT_USER_NAME="GitHub Actions"
            CROMWELL_BUILD_HEARTBEAT_PATTERN="…"
            CROMWELL_BUILD_GENERATE_COVERAGE=true

            CROMWELL_BUILD_EVENT="${GITHUB_EVENT_NAME}"

            if [[ "${GITHUB_REPOSITORY}" == "broadinstitute/cromwell" ]]; then
                CROMWELL_BUILD_IS_SECURE=true
            else
                CROMWELL_BUILD_IS_SECURE=false
            fi

            # Parse refs based to get branch information
            # https://docs.github.com/en/free-pro-team@latest/actions/reference/events-that-trigger-workflows
            if [[ "${GITHUB_REF}" == "refs/tags/"* ]]; then
                CROMWELL_BUILD_BRANCH="${GITHUB_REF#refs/tags/}"
                CROMWELL_BUILD_TAG="${CROMWELL_BUILD_BRANCH}"
            elif [[ "${GITHUB_REF}" == "refs/pull/"* ]]; then
                CROMWELL_BUILD_BRANCH="${GITHUB_HEAD_REF}"
                CROMWELL_BUILD_TAG=""

                github_pr_repository="${GITHUB_REPOSITORY}"
                github_pr_number="${GITHUB_REF}"
                github_pr_number="${github_pr_number#refs/pull/}"
                github_pr_number="${github_pr_number%/merge}"

                # Download more of the git history so we can search for the list modified files later.
                # https://github.community/t/check-pushed-file-changes-with-git-diff-tree-in-github-actions/17220/10
                # https://github.com/actions/checkout/issues/160
                # The '|| true' is there until this is debugged/tested with a forked PR and then may be removed
                git fetch --no-tags --prune --depth=1000 origin +refs/heads/*:refs/remotes/origin/* || true
            else
                CROMWELL_BUILD_BRANCH="${GITHUB_REF#refs/heads/}"
                CROMWELL_BUILD_TAG=""
            fi
            ;;
        "${CROMWELL_BUILD_PROVIDER_CIRCLE}")
            CROMWELL_BUILD_IS_CI=true
            CROMWELL_BUILD_TYPE="${BUILD_TYPE}"
            CROMWELL_BUILD_NUMBER="${CIRCLE_BUILD_NUM}"
            CROMWELL_BUILD_URL="${CIRCLE_BUILD_URL}"
            CROMWELL_BUILD_GIT_USER_EMAIL="builds@circleci.com"
            CROMWELL_BUILD_GIT_USER_NAME="CircleCI"
            CROMWELL_BUILD_HEARTBEAT_PATTERN="…"
            CROMWELL_BUILD_GENERATE_COVERAGE=true

            CROMWELL_BUILD_BRANCH="${CIRCLE_BRANCH:-${CIRCLE_TAG}}"
            CROMWELL_BUILD_TAG="${CIRCLE_TAG:-}"

            local circle_github_repository
            circle_github_repository="${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"

            if [[ "${circle_github_repository}" == "broadinstitute/cromwell" ]]; then
                CROMWELL_BUILD_IS_SECURE=true
            else
                CROMWELL_BUILD_IS_SECURE=false
            fi

            if [[ -n "${CIRCLE_PULL_REQUEST:+set}" ]]; then
                CROMWELL_BUILD_EVENT="pull_request"

                github_pr_repository="${circle_github_repository}"

                # > CIRCLE_PR_NUMBER ... Only available on forked PRs.
                # via: https://circleci.com/docs/2.0/env-vars/#built-in-environment-variables
                # So use https://discuss.circleci.com/t/pipeline-git-base-revision-is-completely-unreliable/38301/11
                github_pr_number="${CIRCLE_PULL_REQUEST##*/}"
            else
                CROMWELL_BUILD_EVENT="push"
            fi
            ;;
        "${CROMWELL_BUILD_PROVIDER_GOOGLE}")
            CROMWELL_BUILD_IS_CI=true
            CROMWELL_BUILD_TYPE="${BUILD_TYPE}"
            CROMWELL_BUILD_NUMBER="${BUILD_ID%%-*}.${BUILD_NAME}"
            CROMWELL_BUILD_URL="https://console.cloud.google.com/cloud-build/builds/${BUILD_ID}?project=${PROJECT_ID}"
            CROMWELL_BUILD_GIT_USER_EMAIL="cloud-build@google.com"
            CROMWELL_BUILD_GIT_USER_NAME="Google Cloud Build"
            CROMWELL_BUILD_HEARTBEAT_PATTERN="…"
            CROMWELL_BUILD_GENERATE_COVERAGE=true

            CROMWELL_BUILD_BRANCH="${BRANCH_NAME:-${TAG_NAME}}"
            CROMWELL_BUILD_TAG="${TAG_NAME:-}"
            CROMWELL_BUILD_IS_SECURE=true

            if [[ -n "${PR_NUMBER:+set}" ]]; then
                CROMWELL_BUILD_EVENT="pull_request"
                github_pr_repository="${OWNER_NAME}/${REPO_NAME}"
                github_pr_number="${PR_NUMBER}"

                # Download more of the git history so we can search for the list modified files later.
                # https://cloud.google.com/cloud-build/docs/automating-builds/create-manage-triggers#including_the_repository_history_in_a_build
                # The '|| true' is there until this is debugged/tested with a forked PR and then may be removed
                git fetch --no-tags --prune --depth=1000 origin +refs/heads/*:refs/remotes/origin/* || true
            else
                CROMWELL_BUILD_EVENT="push"
            fi
            ;;
        "${CROMWELL_BUILD_PROVIDER_JENKINS}")
            # External variables must be passed through in the ENVIRONMENT of src/ci/docker-compose/docker-compose.yml
            CROMWELL_BUILD_IS_CI=true
            CROMWELL_BUILD_IS_SECURE=true
            CROMWELL_BUILD_TYPE="${JENKINS_BUILD_TYPE}"
            CROMWELL_BUILD_BRANCH="${GIT_BRANCH#origin/}"
            CROMWELL_BUILD_EVENT=""
            CROMWELL_BUILD_TAG=""
            CROMWELL_BUILD_NUMBER="${BUILD_NUMBER}"
            CROMWELL_BUILD_URL="${BUILD_URL}"
            CROMWELL_BUILD_GIT_USER_EMAIL="jenkins@jenkins.io"
            CROMWELL_BUILD_GIT_USER_NAME="Jenkins CI"
            CROMWELL_BUILD_HEARTBEAT_PATTERN="…\n"
            CROMWELL_BUILD_GENERATE_COVERAGE=false
            CROMWELL_BUILD_RUN_TESTS=true
            ;;
        "${CROMWELL_BUILD_PROVIDER_CIRCLE}")
            CROMWELL_BUILD_IS_CI=true
            CROMWELL_BUILD_TYPE="${BUILD_TYPE}"
            CROMWELL_BUILD_NUMBER="${CIRCLE_BUILD_NUM}"
            CROMWELL_BUILD_URL="${CIRCLE_BUILD_URL}"
            CROMWELL_BUILD_GIT_USER_EMAIL="builds@circleci.com"
            CROMWELL_BUILD_GIT_USER_NAME="CircleCI"
            CROMWELL_BUILD_HEARTBEAT_PATTERN="…"
            CROMWELL_BUILD_GENERATE_COVERAGE=true
            CROMWELL_BUILD_BRANCH="${CIRCLE_BRANCH:-${CIRCLE_TAG}}"
            CROMWELL_BUILD_TAG="${CIRCLE_TAG:-}"

            local circle_github_repository
            circle_github_repository="${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"

            if [[ "${circle_github_repository}" == "broadinstitute/cromwell" ]]; then
                CROMWELL_BUILD_IS_SECURE=true
            else
                CROMWELL_BUILD_IS_SECURE=false
            fi

            CROMWELL_BUILD_EVENT="pull_request"

            local circle_commit_message
            local circle_force_tests
            local circle_minimal_tests
            if [[ -n "${CIRCLE_COMMIT_RANGE:+set}" ]]; then
                # The commit message to analyze should be the last one in the commit range.
                # This works for both pull_request and push builds, unlike using 'git log HEAD' which
                # gives a merge commit message on pull requests.
                circle_commit_message="$(git log --reverse "${CIRCLE_COMMIT_RANGE}" | tail -n1 2>/dev/null || true)"
            fi

            if [[ -z "${circle_commit_message:-}" ]]; then
                circle_commit_message="$(git log --format=%B --max-count=1 HEAD 2>/dev/null || true)"
            fi

            if [[ "${circle_commit_message}" == *"[force ci]"* ]]; then
                circle_force_tests=true
                circle_minimal_tests=false
            elif [[ "${circle_commit_message}" == *"[minimal ci]"* ]]; then
                circle_force_tests=false
                circle_minimal_tests=true
            else
                circle_force_tests=false
                circle_minimal_tests=false
            fi

            echo "Building for commit message='${circle_commit_message}' with force=${circle_force_tests} and minimal=${circle_minimal_tests}"

            # For solely documentation updates run only checkPublish. Otherwise always run sbt, even for 'push'.
            # This allows quick sanity checks before starting PRs *and* publishing after merges into develop.
            if [[ "${circle_force_tests}" == "true" ]]; then
                CROMWELL_BUILD_RUN_TESTS=true
            elif [[ "${CROMWELL_BUILD_ONLY_DOCS_CHANGED}" == "true" ]] && \
                [[ "${BUILD_TYPE}" != "checkPublish" ]]; then
                CROMWELL_BUILD_RUN_TESTS=false
            elif [[ "${circle_minimal_tests}" == "true" ]] && \
                [[ "${CROMWELL_BUILD_EVENT}" != "push" ]]; then
                CROMWELL_BUILD_RUN_TESTS=false
            elif [[ "${CROMWELL_BUILD_ONLY_SCRIPTS_CHANGED}" == "true" ]] && \
                [[ "${BUILD_TYPE}" != "metadataComparisonPython" ]]; then
                CROMWELL_BUILD_RUN_TESTS=false
            elif [[ "${CROMWELL_BUILD_EVENT}" == "push" ]] && \
                [[ "${BUILD_TYPE}" != "sbt" ]]; then
                CROMWELL_BUILD_RUN_TESTS=false
            else
                CROMWELL_BUILD_RUN_TESTS=true
            fi
            ;;
        *)
            CROMWELL_BUILD_IS_CI=false
            CROMWELL_BUILD_IS_SECURE=true
            CROMWELL_BUILD_TYPE="unknown"
            CROMWELL_BUILD_BRANCH="unknown"
            CROMWELL_BUILD_EVENT="unknown"
            CROMWELL_BUILD_TAG=""
            CROMWELL_BUILD_NUMBER=""
            CROMWELL_BUILD_URL=""
            CROMWELL_BUILD_GIT_USER_EMAIL="unknown.git.user@example.org"
            CROMWELL_BUILD_GIT_USER_NAME="Unknown Git User"
            CROMWELL_BUILD_HEARTBEAT_PATTERN="…"
            CROMWELL_BUILD_GENERATE_COVERAGE="${CROMWELL_BUILD_GENERATE_COVERAGE:-true}"
            CROMWELL_BUILD_RUN_TESTS=true

            local bash_script
            for bash_script in "${BASH_SOURCE[@]}"; do
                if [[ "${bash_script}" != */test.inc.sh ]]; then
                    local build_type_script
                    build_type_script="$(basename "${bash_script}")"
                    build_type_script="${build_type_script#test}"
                    build_type_script="${build_type_script%.sh}"
                    build_type_script="$(tr '[:upper:]' '[:lower:]' <<< "${build_type_script:0:1}")${build_type_script:1}"
                    CROMWELL_BUILD_TYPE="${build_type_script}"
                    break
                fi
            done
            ;;
    esac

    # (Comments also refactored from original conditional logic)

    # For solely documentation updates run only checkPublish. Otherwise always run sbt, even for 'push'.
    # This allows quick sanity checks before starting PRs *and* publishing after merges into develop.

    # Value of the `TRAVIS_BRANCH` variable depends on type of Travis build: if it is pull request build, the value
    # will be the name of the branch targeted by the pull request, and for push builds it will be the name of the
    # branch. So, in case of push builds `git diff` will always return empty result. This is why we only use this short
    # circuiting logic for pull request builds

    CROMWELL_BUILD_RUN_TESTS=true

    local github_pr_files_changed
    local github_pr_only_docs
    local github_pr_only_scripts
    local git_commit_message
    local git_commit_force_tests
    local git_commit_minimal_tests

    github_pr_files_changed=""
    github_pr_only_docs=false
    github_pr_only_scripts=false
    git_commit_message=""
    git_commit_force_tests=false
    git_commit_minimal_tests=false

    if [[ "${CROMWELL_BUILD_EVENT}" == "pull_request" ]] && \
        [[ -n "${github_pr_repository:+set}" ]] && \
        [[ -n "${github_pr_number:+set}" ]]; then

        local github_pr_json
        local git_commit_base
        local git_commit_head

        github_pr_json="$(
            cromwell::private::get_github_pr_json \
                "${github_pr_repository}" \
                "${github_pr_number}"
        )"
        git_commit_base="$(jq --raw-output .base.sha <<< "${github_pr_json}")"
        git_commit_head="$(jq --raw-output .head.sha <<< "${github_pr_json}")"
        # This works for pull_request unlike using 'git log HEAD' which gives a merge commit message on pull requests.
        git_commit_message="$(git log --format=%B --max-count=1 "${git_commit_head}" 2>/dev/null || true)"
        github_pr_files_changed="$(git diff --name-only "${git_commit_base}...${git_commit_head}" 2>/dev/null || true)"
    fi

    if [[ -z "${git_commit_message:-}" ]]; then
        git_commit_message="$(git log --format=%B --max-count=1 HEAD 2>/dev/null || true)"
    fi

    if [[ -n "${github_pr_files_changed:+set}" ]]; then
        github_pr_only_docs="$(
            cromwell::private::check_if_files_changed \
                "${github_pr_files_changed}" \
                "^mkdocs.yml|^docs/|^CHANGELOG.md"
        )"
        github_pr_only_scripts="$(
            cromwell::private::check_if_files_changed \
                "${github_pr_files_changed}" \
                "^src/ci/bin/testMetadataComparisonPython.sh|^scripts/"
        )"
    fi

    if [[ "${git_commit_message}" == *"[force ci]"* ]]; then
        git_commit_force_tests=true
        git_commit_minimal_tests=false
    elif [[ "${git_commit_message}" == *"[minimal ci]"* ]]; then
        git_commit_force_tests=false
        git_commit_minimal_tests=true
    fi

    if [[ "${github_pr_only_docs}" == "true" ]] && [[ "${CROMWELL_BUILD_TYPE}" != "checkPublish" ]]; then
        CROMWELL_BUILD_RUN_TESTS=false
    fi

    if [[ "${git_commit_minimal_tests}" == "true" ]] && [[ "${CROMWELL_BUILD_EVENT}" != "push" ]]; then
        CROMWELL_BUILD_RUN_TESTS=false
    fi

    if [[ "${github_pr_only_scripts}" == "true" ]] && [[ "${CROMWELL_BUILD_TYPE}" != "metadataComparisonPython" ]]; then
        CROMWELL_BUILD_RUN_TESTS=false
    fi

    if [[ "${CROMWELL_BUILD_EVENT}" == "push" ]] && [[ "${CROMWELL_BUILD_TYPE}" != "sbt" ]]; then
        CROMWELL_BUILD_RUN_TESTS=false
    fi

    if [[ "${git_commit_force_tests}" == "true" ]]; then
        CROMWELL_BUILD_RUN_TESTS=true
    fi

    echo "DEBUG: github_pr_repository='${github_pr_repository}'"
    echo "DEBUG: github_pr_number='${github_pr_number}'"
    echo "DEBUG: github_pr_files_changed='${github_pr_files_changed}'"
    echo "DEBUG: github_pr_only_docs='${github_pr_only_docs}'"
    echo "DEBUG: github_pr_only_scripts='${github_pr_only_scripts}'"
    echo "DEBUG: git_commit_message='${git_commit_message}'"
    echo "DEBUG: git_commit_force_tests='${git_commit_force_tests}'"
    echo "DEBUG: git_commit_minimal_tests='${git_commit_minimal_tests}'"

    local backend_type
    backend_type="${CROMWELL_BUILD_TYPE}"
    backend_type="${backend_type#centaurEngineUpgrade}"
    backend_type="${backend_type#centaurPapiUpgrade}"
    backend_type="${backend_type#centaurWdlUpgrade}"
    backend_type="${backend_type#centaurHoricromtal}"
    backend_type="${backend_type#centaur}"
    backend_type="${backend_type#conformance}"
    backend_type="$(echo "${backend_type}" | sed 's/\([A-Z]\)/_\1/g' | tr '[:upper:]' '[:lower:]' | cut -c 2-)"
    CROMWELL_BUILD_BACKEND_TYPE="${backend_type}"

    if [[ "${CROMWELL_BUILD_TYPE}" == conformance* ]]; then
        CROMWELL_BUILD_SBT_ASSEMBLY_COMMAND="server/assembly centaurCwlRunner/assembly"
    else
        CROMWELL_BUILD_SBT_ASSEMBLY_COMMAND="assembly"
    fi

    if [[ "${CROMWELL_BUILD_GENERATE_COVERAGE}" == "true" ]]; then
        CROMWELL_BUILD_SBT_COVERAGE_COMMAND="coverage"
    else
        CROMWELL_BUILD_SBT_COVERAGE_COMMAND=""
    fi

    CROMWELL_BUILD_SBT_INCLUDE="${BUILD_SBT_INCLUDE:-}"
    CROMWELL_BUILD_SBT_EXCLUDE="${BUILD_SBT_EXCLUDE:-}"

    case "${CROMWELL_BUILD_TYPE}" in
        centaurPapiUpgradePapiV2alpha1*)
            CROMWELL_BUILD_CROMWELL_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/papi_v2alpha1_v2beta_upgrade_application.conf"
            ;;
        centaurPapiUpgradeNewWorkflowsPapiV2alpha1*)
            CROMWELL_BUILD_CROMWELL_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/papi_v2alpha1_v2beta_upgrade_application.conf"
            ;;
        centaurHoricromtalPapiV2alpha1*)
            CROMWELL_BUILD_CROMWELL_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/papi_v2alpha1_horicromtal_application.conf"
            ;;
        centaurHoricromtalPapiV2beta*)
            CROMWELL_BUILD_CROMWELL_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/papi_v2beta_horicromtal_application.conf"
            ;;
        centaurHoricromtalEngineUpgrade*)
            CROMWELL_BUILD_CROMWELL_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/papi_v2alpha1_horicromtal_application.conf"
            ;;
        *)
            CROMWELL_BUILD_CROMWELL_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/${CROMWELL_BUILD_BACKEND_TYPE}_application.conf"
            ;;
    esac

    if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]]; then
        CROMWELL_BUILD_DOCKER_TAG="${CROMWELL_BUILD_PROVIDER}-${CROMWELL_BUILD_NUMBER}"
    else
        CROMWELL_BUILD_DOCKER_TAG="${CROMWELL_BUILD_PROVIDER}-${CROMWELL_BUILD_TYPE}-${CROMWELL_BUILD_GIT_HASH_SUFFIX}"
    fi

    # Trim and replace invalid characters in the docker tag
    # https://docs.docker.com/engine/reference/commandline/tag/#extended-description
    CROMWELL_BUILD_DOCKER_TAG="${CROMWELL_BUILD_DOCKER_TAG:0:128}"
    CROMWELL_BUILD_DOCKER_TAG="${CROMWELL_BUILD_DOCKER_TAG//[^a-zA-Z0-9.-]/_}"

    CROMWELL_BUILD_REQUIRES_SECURE="${CROMWELL_BUILD_REQUIRES_SECURE-false}"
    CROMWELL_BUILD_REQUIRES_PRIOR_VERSION="${CROMWELL_BUILD_REQUIRES_PRIOR_VERSION-false}"

    local hours_to_minutes
    hours_to_minutes=60
    CROMWELL_BUILD_HEARTBEAT_MINUTES=$((20 * hours_to_minutes))

    export CROMWELL_BUILD_BACKEND_TYPE
    export CROMWELL_BUILD_BRANCH
    export CROMWELL_BUILD_CROMWELL_CONFIG
    export CROMWELL_BUILD_CROMWELL_LOG
    export CROMWELL_BUILD_CURRENT_VERSION_NUMBER
    export CROMWELL_BUILD_DOCKER_DIRECTORY
    export CROMWELL_BUILD_DOCKER_TAG
    export CROMWELL_BUILD_EVENT
    export CROMWELL_BUILD_EXIT_FUNCTIONS
    export CROMWELL_BUILD_GENERATE_COVERAGE
    export CROMWELL_BUILD_GIT_HASH_SUFFIX
    export CROMWELL_BUILD_GIT_SECRETS_COMMIT
    export CROMWELL_BUILD_GIT_SECRETS_DIRECTORY
    export CROMWELL_BUILD_GIT_USER_EMAIL
    export CROMWELL_BUILD_GIT_USER_NAME
    export CROMWELL_BUILD_HEARTBEAT_MINUTES
    export CROMWELL_BUILD_HEARTBEAT_PATTERN
    export CROMWELL_BUILD_HOME_DIRECTORY
    export CROMWELL_BUILD_IS_CI
    export CROMWELL_BUILD_IS_HOTFIX
    export CROMWELL_BUILD_IS_SECURE
    export CROMWELL_BUILD_IS_VIRTUAL_ENV
    export CROMWELL_BUILD_LOG_DIRECTORY
    export CROMWELL_BUILD_NUMBER
    export CROMWELL_BUILD_OS
    export CROMWELL_BUILD_OS_DARWIN
    export CROMWELL_BUILD_OS_LINUX
    export CROMWELL_BUILD_PRIOR_VERSION_NUMBER
    export CROMWELL_BUILD_PROVIDER
    export CROMWELL_BUILD_PROVIDER_CIRCLE
    export CROMWELL_BUILD_PROVIDER_GITHUB
    export CROMWELL_BUILD_PROVIDER_GOOGLE
    export CROMWELL_BUILD_PROVIDER_JENKINS
    export CROMWELL_BUILD_PROVIDER_TRAVIS
    export CROMWELL_BUILD_PROVIDER_UNKNOWN
    export CROMWELL_BUILD_REQUIRES_PRIOR_VERSION
    export CROMWELL_BUILD_REQUIRES_SECURE
    export CROMWELL_BUILD_RESOURCES_DIRECTORY
    export CROMWELL_BUILD_RESOURCES_SOURCES
    export CROMWELL_BUILD_ROOT_DIRECTORY
    export CROMWELL_BUILD_RUN_TESTS
    export CROMWELL_BUILD_SBT_ASSEMBLY_COMMAND
    export CROMWELL_BUILD_SBT_COVERAGE_COMMAND
    export CROMWELL_BUILD_SBT_EXCLUDE
    export CROMWELL_BUILD_SBT_INCLUDE
    export CROMWELL_BUILD_SCRIPTS_DIRECTORY
    export CROMWELL_BUILD_TAG
    export CROMWELL_BUILD_TYPE
    export CROMWELL_BUILD_UNIT_TEST_EXCLUDE_TAGS
    export CROMWELL_BUILD_URL
    export CROMWELL_BUILD_VAULT_EXECUTABLE
    export CROMWELL_BUILD_VAULT_ZIP
    export CROMWELL_BUILD_WAIT_FOR_IT_BRANCH
    export CROMWELL_BUILD_WAIT_FOR_IT_FILENAME
    export CROMWELL_BUILD_WAIT_FOR_IT_SCRIPT
    export CROMWELL_BUILD_WAIT_FOR_IT_URL
}

cromwell::private::echo_build_variables() {
    echo "CROMWELL_BUILD_IS_CI='${CROMWELL_BUILD_IS_CI}'"
    echo "CROMWELL_BUILD_IS_SECURE='${CROMWELL_BUILD_IS_SECURE}'"
    echo "CROMWELL_BUILD_REQUIRES_SECURE='${CROMWELL_BUILD_REQUIRES_SECURE}'"
    echo "CROMWELL_BUILD_TYPE='${CROMWELL_BUILD_TYPE}'"
    echo "CROMWELL_BUILD_BRANCH='${CROMWELL_BUILD_BRANCH}'"
    echo "CROMWELL_BUILD_IS_HOTFIX='${CROMWELL_BUILD_IS_HOTFIX}'"
    echo "CROMWELL_BUILD_CURRENT_VERSION_NUMBER='${CROMWELL_BUILD_CURRENT_VERSION_NUMBER}'"
    echo "CROMWELL_BUILD_PRIOR_VERSION_NUMBER='${CROMWELL_BUILD_PRIOR_VERSION_NUMBER}'"
    echo "CROMWELL_BUILD_EVENT='${CROMWELL_BUILD_EVENT}'"
    echo "CROMWELL_BUILD_TAG='${CROMWELL_BUILD_TAG}'"
    echo "CROMWELL_BUILD_NUMBER='${CROMWELL_BUILD_NUMBER}'"
    echo "CROMWELL_BUILD_PROVIDER='${CROMWELL_BUILD_PROVIDER}'"
    echo "CROMWELL_BUILD_OS='${CROMWELL_BUILD_OS}'"
    echo "CROMWELL_BUILD_URL='${CROMWELL_BUILD_URL}'"
}

# Create environment variables used by the DatabaseTestKit and cromwell::private::create_centaur_variables()
cromwell::private::create_database_variables() {
    CROMWELL_BUILD_DATABASE_USERNAME="cromwell"
    CROMWELL_BUILD_DATABASE_PASSWORD="test"
    CROMWELL_BUILD_DATABASE_SCHEMA="cromwell_test"

    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_TRAVIS}"|\
        "${CROMWELL_BUILD_PROVIDER_GOOGLE}"|\
        "${CROMWELL_BUILD_PROVIDER_GITHUB}"|\
        "${CROMWELL_BUILD_PROVIDER_CIRCLE}")
            # Define a docker tag to spin up the new database containers
            CROMWELL_BUILD_HSQLDB="${BUILD_HSQLDB-}"
            CROMWELL_BUILD_MARIADB_DOCKER_TAG="${BUILD_MARIADB-}"
            CROMWELL_BUILD_MYSQL_DOCKER_TAG="${BUILD_MYSQL-}"
            CROMWELL_BUILD_POSTGRESQL_DOCKER_TAG="${BUILD_POSTGRESQL-}"
            CROMWELL_BUILD_SQLITE="${BUILD_SQLITE-}"
            ;;
        "${CROMWELL_BUILD_PROVIDER_JENKINS}"|\
        *)
            # NOTE: Jenkins uses src/ci/docker-compose/docker-compose.yml.
            # We don't define a docker tag because the docker-compose has already spun up the database containers by the
            # time this script is run. Other variables here must match the database service names and settings the yaml.
            CROMWELL_BUILD_HSQLDB="${CROMWELL_BUILD_HSQLDB-}"
            CROMWELL_BUILD_MARIADB_DOCKER_TAG=""
            CROMWELL_BUILD_MYSQL_DOCKER_TAG=""
            CROMWELL_BUILD_POSTGRESQL_DOCKER_TAG=""
            CROMWELL_BUILD_SQLITE="${CROMWELL_BUILD_SQLITE-}"
            ;;
    esac

    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_TRAVIS}"|\
        "${CROMWELL_BUILD_PROVIDER_GITHUB}"|\
        "${CROMWELL_BUILD_PROVIDER_CIRCLE}")
            # These use docker networking to connect to the container published ports from localhost
            CROMWELL_BUILD_MARIADB_HOSTNAME="localhost"
            CROMWELL_BUILD_MARIADB_PORT="13306"
            CROMWELL_BUILD_MYSQL_HOSTNAME="localhost"
            CROMWELL_BUILD_MYSQL_PORT="3306"
            CROMWELL_BUILD_POSTGRESQL_HOSTNAME="localhost"
            CROMWELL_BUILD_POSTGRESQL_PORT="5432"
            ;;
        "${CROMWELL_BUILD_PROVIDER_GOOGLE}")
            # These use docker networking to connect to the internal ports using the generated container names
            CROMWELL_BUILD_MARIADB_HOSTNAME="$(cromwell::private::get_docker_name "mariadb:${CROMWELL_BUILD_MARIADB_DOCKER_TAG}")"
            CROMWELL_BUILD_MARIADB_PORT="3306"
            CROMWELL_BUILD_MYSQL_HOSTNAME="$(cromwell::private::get_docker_name "mysql:${CROMWELL_BUILD_MYSQL_DOCKER_TAG}")"
            CROMWELL_BUILD_MYSQL_PORT="3306"
            CROMWELL_BUILD_POSTGRESQL_HOSTNAME="$(cromwell::private::get_docker_name "postgres:${CROMWELL_BUILD_POSTGRESQL_DOCKER_TAG}")"
            CROMWELL_BUILD_POSTGRESQL_PORT="5432"
            ;;
        "${CROMWELL_BUILD_PROVIDER_JENKINS}")
            # These use docker networking to connect to the internal ports using the names from docker-compose.yml
            CROMWELL_BUILD_MARIADB_HOSTNAME="mariadb-db"
            CROMWELL_BUILD_MARIADB_PORT="3306"
            CROMWELL_BUILD_MYSQL_HOSTNAME="mysqldb-db"
            CROMWELL_BUILD_MYSQL_PORT="3306"
            CROMWELL_BUILD_POSTGRESQL_HOSTNAME="postgresdb-db"
            CROMWELL_BUILD_POSTGRESQL_PORT="5432"
            ;;
        *)
            if [[ -z "${CROMWELL_BUILD_DOCKER_LOCALHOST-}" ]]; then
                CROMWELL_BUILD_DOCKER_LOCALHOST="localhost"
            fi

            CROMWELL_BUILD_MARIADB_HOSTNAME="${CROMWELL_BUILD_MARIADB_HOSTNAME-${CROMWELL_BUILD_DOCKER_LOCALHOST}}"
            CROMWELL_BUILD_MARIADB_PORT="${CROMWELL_BUILD_MARIADB_PORT-13306}"
            CROMWELL_BUILD_MYSQL_HOSTNAME="${CROMWELL_BUILD_MYSQL_HOSTNAME-${CROMWELL_BUILD_DOCKER_LOCALHOST}}"
            CROMWELL_BUILD_MYSQL_PORT="${CROMWELL_BUILD_MYSQL_PORT-3306}"
            CROMWELL_BUILD_POSTGRESQL_HOSTNAME="${CROMWELL_BUILD_POSTGRESQL_HOSTNAME-${CROMWELL_BUILD_DOCKER_LOCALHOST}}"
            CROMWELL_BUILD_POSTGRESQL_PORT="${CROMWELL_BUILD_POSTGRESQL_PORT-5432}"
            ;;
    esac

    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_GOOGLE}")
            # We're inside a docker where GCB has already created a network for us
            # https://cloud.google.com/cloud-build/docs/overview#build_configuration_and_build_steps
            # https://cloud.google.com/cloud-build/docs/build-config#network
            CROMWELL_BUILD_DATABASE_NETWORK="cloudbuild"
            ;;
        "${CROMWELL_BUILD_PROVIDER_TRAVIS}"|\
        "${CROMWELL_BUILD_PROVIDER_GITHUB}"|\
        "${CROMWELL_BUILD_PROVIDER_CIRCLE}"|\
        "${CROMWELL_BUILD_PROVIDER_JENKINS}"|\
        *)
            # Use the default network
            # https://docs.docker.com/engine/reference/run/#network-settings
            # Not really used in Jenkins as docker-compose spins up the network
            CROMWELL_BUILD_DATABASE_NETWORK="bridge"
            ;;
    esac

    export CROMWELL_BUILD_DATABASE_USERNAME
    export CROMWELL_BUILD_DATABASE_NETWORK
    export CROMWELL_BUILD_DATABASE_PASSWORD
    export CROMWELL_BUILD_DATABASE_SCHEMA
    export CROMWELL_BUILD_HSQLDB
    export CROMWELL_BUILD_MARIADB_DOCKER_TAG
    export CROMWELL_BUILD_MARIADB_HOSTNAME
    export CROMWELL_BUILD_MARIADB_PORT
    export CROMWELL_BUILD_MYSQL_DOCKER_TAG
    export CROMWELL_BUILD_MYSQL_HOSTNAME
    export CROMWELL_BUILD_MYSQL_PORT
    export CROMWELL_BUILD_POSTGRESQL_DOCKER_TAG
    export CROMWELL_BUILD_POSTGRESQL_HOSTNAME
    export CROMWELL_BUILD_POSTGRESQL_PORT
    export CROMWELL_BUILD_SQLITE
}

cromwell::private::create_centaur_variables() {
    CROMWELL_BUILD_CENTAUR_TYPE_STANDARD="standard"
    CROMWELL_BUILD_CENTAUR_TYPE_INTEGRATION="integration"
    CROMWELL_BUILD_CENTAUR_TYPE_ENGINE_UPGRADE="engineUpgrade"
    CROMWELL_BUILD_CENTAUR_TYPE_PAPI_UPGRADE="papiUpgrade"
    CROMWELL_BUILD_CENTAUR_TYPE_PAPI_UPGRADE_NEW_WORKFLOWS="papiUpgradeNewWorkflows"
    CROMWELL_BUILD_CENTAUR_TYPE_HORICROMTAL_ENGINE_UPGRADE="horicromtalEngineUpgrade"
    CROMWELL_BUILD_CENTAUR_TYPE_HORICROMTAL="horicromtal"

    case "${CROMWELL_BUILD_TYPE}" in
        centaurEngineUpgrade*)
            CROMWELL_BUILD_CENTAUR_TYPE="${CROMWELL_BUILD_CENTAUR_TYPE_ENGINE_UPGRADE}"
            ;;
        centaurPapiUpgradeNewWorkflows*)
            CROMWELL_BUILD_CENTAUR_TYPE="${CROMWELL_BUILD_CENTAUR_TYPE_PAPI_UPGRADE_NEW_WORKFLOWS}"
            ;;
        centaurPapiUpgrade*)
            CROMWELL_BUILD_CENTAUR_TYPE="${CROMWELL_BUILD_CENTAUR_TYPE_PAPI_UPGRADE}"
            ;;
        centaurHoricromtalEngineUpgrade*)
            CROMWELL_BUILD_CENTAUR_TYPE="${CROMWELL_BUILD_CENTAUR_TYPE_HORICROMTAL_ENGINE_UPGRADE}"
            ;;
        centaurHoricromtal*)
            CROMWELL_BUILD_CENTAUR_TYPE="${CROMWELL_BUILD_CENTAUR_TYPE_HORICROMTAL}"
            ;;
        *)
            # Only set the type if Jenkins, etc. has not already set the centaur type
            if [[ -z "${CROMWELL_BUILD_CENTAUR_TYPE-}" ]]; then
                CROMWELL_BUILD_CENTAUR_TYPE="${CROMWELL_BUILD_CENTAUR_TYPE_STANDARD}"
            fi
            ;;
    esac

    CROMWELL_BUILD_CENTAUR_RESOURCES="${CROMWELL_BUILD_ROOT_DIRECTORY}/centaur/src/main/resources"
    case "${CROMWELL_BUILD_CENTAUR_TYPE}" in
        "${CROMWELL_BUILD_CENTAUR_TYPE_HORICROMTAL}")
            # Use the standard test cases despite the horicromtal Centaur build type.
            CROMWELL_BUILD_CENTAUR_TEST_DIRECTORY="${CROMWELL_BUILD_CENTAUR_RESOURCES}/standardTestCases"
            CROMWELL_BUILD_CENTAUR_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/centaur_application_horicromtal.conf"
            ;;
        "${CROMWELL_BUILD_CENTAUR_TYPE_HORICROMTAL_ENGINE_UPGRADE}")
            # Use the engine upgrade test cases despite the horicromtal Centaur build type.
            CROMWELL_BUILD_CENTAUR_TEST_DIRECTORY="${CROMWELL_BUILD_CENTAUR_RESOURCES}/engineUpgradeTestCases"
            # Special horicromtal engine upgrade Centaur config with horicromtal assertions turned off.
            CROMWELL_BUILD_CENTAUR_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/centaur_application_horicromtal_no_assert.conf"
            ;;
        *)
            CROMWELL_BUILD_CENTAUR_TEST_DIRECTORY="${CROMWELL_BUILD_CENTAUR_RESOURCES}/${CROMWELL_BUILD_CENTAUR_TYPE}TestCases"
            CROMWELL_BUILD_CENTAUR_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/centaur_application.conf"
            ;;
    esac

    CROMWELL_BUILD_CENTAUR_LOG="${CROMWELL_BUILD_LOG_DIRECTORY}/centaur.log"

    local hsqldb_jdbc_args
    local sqlite_jdbc_args
    local mariadb_jdbc_url
    local mysql_jdbc_url
    local postgresql_jdbc_url

    hsqldb_jdbc_args="shutdown=false"
    hsqldb_jdbc_args="${hsqldb_jdbc_args};hsqldb.tx=mvcc"
    hsqldb_jdbc_args="${hsqldb_jdbc_args};hsqldb.large_data=true"
    hsqldb_jdbc_args="${hsqldb_jdbc_args};hsqldb.result_max_memory_rows=10000"
    hsqldb_jdbc_args="${hsqldb_jdbc_args};hsqldb.applog=1"
    hsqldb_jdbc_args="${hsqldb_jdbc_args};hsqldb.default_table_type=cached"
    hsqldb_jdbc_args="${hsqldb_jdbc_args};hsqldb.large_data=true"
    hsqldb_jdbc_args="${hsqldb_jdbc_args};hsqldb.lob_compressed=true"
    hsqldb_jdbc_args="${hsqldb_jdbc_args};hsqldb.script_format=3"

    sqlite_jdbc_args="foreign_keys=true"
    sqlite_jdbc_args="${sqlite_jdbc_args}&date_class=text"

    mariadb_jdbc_url="jdbc:mariadb://${CROMWELL_BUILD_MARIADB_HOSTNAME}:${CROMWELL_BUILD_MARIADB_PORT}/${CROMWELL_BUILD_DATABASE_SCHEMA}?rewriteBatchedStatements=true"
    mysql_jdbc_url="jdbc:mysql://${CROMWELL_BUILD_MYSQL_HOSTNAME}:${CROMWELL_BUILD_MYSQL_PORT}/${CROMWELL_BUILD_DATABASE_SCHEMA}?allowPublicKeyRetrieval=true&useSSL=false&rewriteBatchedStatements=true&serverTimezone=UTC&useInformationSchema=true"
    postgresql_jdbc_url="jdbc:postgresql://${CROMWELL_BUILD_POSTGRESQL_HOSTNAME}:${CROMWELL_BUILD_POSTGRESQL_PORT}/${CROMWELL_BUILD_DATABASE_SCHEMA}?reWriteBatchedInserts=true"

    # Pick **one** of the databases to run Centaur against
    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_TRAVIS}"|\
        "${CROMWELL_BUILD_PROVIDER_GITHUB}"|\
        "${CROMWELL_BUILD_PROVIDER_GOOGLE}"|\
        "${CROMWELL_BUILD_PROVIDER_CIRCLE}")

            if [[ "${CROMWELL_BUILD_HSQLDB:-false}" == "true" ]]; then
                CROMWELL_BUILD_CENTAUR_SLICK_PROFILE="slick.jdbc.HsqldbProfile$"
                CROMWELL_BUILD_CENTAUR_JDBC_DRIVER="org.hsqldb.jdbcDriver"
                CROMWELL_BUILD_CENTAUR_JDBC_URL="jdbc:hsqldb:file:${CROMWELL_BUILD_RESOURCES_DIRECTORY}/cromwell-hsqldb;${hsqldb_jdbc_args}"
                CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL="jdbc:hsqldb:file:${CROMWELL_BUILD_RESOURCES_DIRECTORY}/metadata-hsqldb;${hsqldb_jdbc_args}"
                CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS=1

            elif [[ "${CROMWELL_BUILD_SQLITE:-false}" == "true" ]]; then
                CROMWELL_BUILD_CENTAUR_SLICK_PROFILE="slick.jdbc.SQLiteProfile$"
                CROMWELL_BUILD_CENTAUR_JDBC_DRIVER="org.sqlite.JDBC"
                CROMWELL_BUILD_CENTAUR_JDBC_URL="jdbc:sqlite:file:${CROMWELL_BUILD_RESOURCES_DIRECTORY}/cromwell.sqlite?${sqlite_jdbc_args}"
                CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL="jdbc:sqlite:file:${CROMWELL_BUILD_RESOURCES_DIRECTORY}/metadata.sqlite?${sqlite_jdbc_args}"
                CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS=1

            elif [[ -n "${CROMWELL_BUILD_MYSQL_DOCKER_TAG:+set}" ]]; then
                CROMWELL_BUILD_CENTAUR_SLICK_PROFILE="slick.jdbc.MySQLProfile$"
                CROMWELL_BUILD_CENTAUR_JDBC_DRIVER="com.mysql.cj.jdbc.Driver"
                CROMWELL_BUILD_CENTAUR_JDBC_URL="${mysql_jdbc_url}"
                CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL="${mysql_jdbc_url}"
                CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS=20

            elif [[ -n "${CROMWELL_BUILD_MARIADB_DOCKER_TAG:+set}" ]]; then
                CROMWELL_BUILD_CENTAUR_SLICK_PROFILE="slick.jdbc.MySQLProfile$"
                CROMWELL_BUILD_CENTAUR_JDBC_DRIVER="org.mariadb.jdbc.Driver"
                CROMWELL_BUILD_CENTAUR_JDBC_URL="${mariadb_jdbc_url}"
                CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL="${mariadb_jdbc_url}"
                CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS=20

            elif [[ -n "${CROMWELL_BUILD_POSTGRESQL_DOCKER_TAG:+set}" ]]; then
                CROMWELL_BUILD_CENTAUR_SLICK_PROFILE="slick.jdbc.PostgresProfile$"
                CROMWELL_BUILD_CENTAUR_JDBC_DRIVER="org.postgresql.Driver"
                CROMWELL_BUILD_CENTAUR_JDBC_URL="${postgresql_jdbc_url}"
                CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL="${postgresql_jdbc_url}"
                CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS=20

            else
                echo "Error: Unable to determine which RDBMS to use for Centaur." >&2
                exit 1

            fi

            CROMWELL_BUILD_CENTAUR_TEST_ADDITIONAL_PARAMETERS=
            ;;
        "${CROMWELL_BUILD_PROVIDER_JENKINS}")
            CROMWELL_BUILD_CENTAUR_SLICK_PROFILE="slick.jdbc.MySQLProfile$"
            CROMWELL_BUILD_CENTAUR_JDBC_DRIVER="com.mysql.cj.jdbc.Driver"
            CROMWELL_BUILD_CENTAUR_JDBC_URL="${mysql_jdbc_url}"
            CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL="${mysql_jdbc_url}"
            CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS=20
            CROMWELL_BUILD_CENTAUR_TEST_ADDITIONAL_PARAMETERS="${CENTAUR_TEST_ADDITIONAL_PARAMETERS-}"
            ;;
        *)
            CROMWELL_BUILD_CENTAUR_SLICK_PROFILE="${CROMWELL_BUILD_CENTAUR_SLICK_PROFILE-slick.jdbc.MySQLProfile\$}"
            CROMWELL_BUILD_CENTAUR_JDBC_DRIVER="${CROMWELL_BUILD_CENTAUR_JDBC_DRIVER-com.mysql.cj.jdbc.Driver}"
            CROMWELL_BUILD_CENTAUR_JDBC_URL="${CROMWELL_BUILD_CENTAUR_JDBC_URL-${mysql_jdbc_url}}"
            CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL="${CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL-${mysql_jdbc_url}}"
            CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS="${CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS-20}"
            CROMWELL_BUILD_CENTAUR_TEST_ADDITIONAL_PARAMETERS=
            ;;
    esac

    case "${CROMWELL_BUILD_CENTAUR_TYPE}" in
        "${CROMWELL_BUILD_CENTAUR_TYPE_INTEGRATION}")
            CROMWELL_BUILD_CENTAUR_READ_LINES_LIMIT=512000
            CROMWELL_BUILD_CENTAUR_MAX_WORKFLOW_LENGTH="10 hours"
            ;;
        *)
            CROMWELL_BUILD_CENTAUR_READ_LINES_LIMIT=128000
            CROMWELL_BUILD_CENTAUR_MAX_WORKFLOW_LENGTH="90 minutes"
            ;;
    esac

    # Setup the networking for accessing the horicromtal docker-compose instances
    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_GOOGLE}")
            # Google Cloud Build tests run in a container so be sure to use the same network
            # https://cloud.google.com/cloud-build/docs/overview#build_configuration_and_build_steps
            # https://cloud.google.com/cloud-build/docs/build-config#network
            CROMWELL_BUILD_HORICROMTAL_NETWORK="cloudbuild"
            # Match the hostname to the container_name used in the docker-compose-horicromtal.yml so that the container
            # may be accessed by name from *this* container's existing cloudbuild network
            # https://docs.docker.com/compose/compose-file/compose-file-v2/#container_name
            CROMWELL_BUILD_HORICROMTAL_CONTAINER="front-back"
            CROMWELL_BUILD_HORICROMTAL_HOSTNAME="front-back"
            # Keeping the same port used by CromwellManager.ManagedCromwellPort even though it doesn't have to match
            CROMWELL_BUILD_HORICROMTAL_PORT=8008
            ;;
        *)
            # The horicromtal docker-compose setup uses host networking to access the database
            CROMWELL_BUILD_HORICROMTAL_NETWORK="host"
            # Since the docker-compose network is using host then we can access the container via localhost
            CROMWELL_BUILD_HORICROMTAL_CONTAINER="front-back"
            CROMWELL_BUILD_HORICROMTAL_HOSTNAME="localhost"
            # Keeping the same port used by CromwellManager.ManagedCromwellPort even though it doesn't have to match
            CROMWELL_BUILD_HORICROMTAL_PORT=8008
            ;;
    esac

    CROMWELL_BUILD_CENTAUR_256_BITS_KEY="$(dd bs=1 count=32 if=/dev/urandom 2> /dev/null | base64 | tr -d '\n')"

    export CROMWELL_BUILD_CENTAUR_256_BITS_KEY
    export CROMWELL_BUILD_CENTAUR_CONFIG
    export CROMWELL_BUILD_CENTAUR_JDBC_DRIVER
    export CROMWELL_BUILD_CENTAUR_JDBC_URL
    export CROMWELL_BUILD_CENTAUR_JDBC_METADATA_URL
    export CROMWELL_BUILD_CENTAUR_JDBC_NUM_THREADS
    export CROMWELL_BUILD_CENTAUR_LOG
    export CROMWELL_BUILD_CENTAUR_MAX_WORKFLOW_LENGTH
    export CROMWELL_BUILD_CENTAUR_PRIOR_JDBC_DRIVER
    export CROMWELL_BUILD_CENTAUR_PRIOR_JDBC_URL
    export CROMWELL_BUILD_CENTAUR_PRIOR_SLICK_PROFILE
    export CROMWELL_BUILD_CENTAUR_READ_LINES_LIMIT
    export CROMWELL_BUILD_CENTAUR_RESOURCES
    export CROMWELL_BUILD_CENTAUR_SLICK_PROFILE
    export CROMWELL_BUILD_CENTAUR_TEST_ADDITIONAL_PARAMETERS
    export CROMWELL_BUILD_CENTAUR_TEST_DIRECTORY
    export CROMWELL_BUILD_CENTAUR_TYPE
    export CROMWELL_BUILD_CENTAUR_TYPE_ENGINE_UPGRADE
    export CROMWELL_BUILD_CENTAUR_TYPE_INTEGRATION
    export CROMWELL_BUILD_CENTAUR_TYPE_STANDARD
    export CROMWELL_BUILD_CENTAUR_TYPE_INTEGRATION
    export CROMWELL_BUILD_CENTAUR_TYPE_ENGINE_UPGRADE
    export CROMWELL_BUILD_DOCKER_TAG
    export CROMWELL_BUILD_HORICROMTAL_CONTAINER
    export CROMWELL_BUILD_HORICROMTAL_HOSTNAME
    export CROMWELL_BUILD_HORICROMTAL_NETWORK
    export CROMWELL_BUILD_HORICROMTAL_PORT
}

cromwell::private::create_conformance_variables() {
    CROMWELL_BUILD_CWL_RUNNER_MODE="${CROMWELL_BUILD_BACKEND_TYPE}"
    CROMWELL_BUILD_CWL_TOOL_VERSION="3.0.20200724003302"
    CROMWELL_BUILD_CWL_TEST_VERSION="1.0.20190228134645"
    CROMWELL_BUILD_CWL_TEST_COMMIT="1f501e38ff692a408e16b246ac7d64d32f0822c2" # use known git hash to avoid changes
    CROMWELL_BUILD_CWL_TEST_RUNNER="${CROMWELL_BUILD_ROOT_DIRECTORY}/centaurCwlRunner/src/bin/centaur-cwl-runner.bash"
    CROMWELL_BUILD_CWL_TEST_DIRECTORY="${CROMWELL_BUILD_ROOT_DIRECTORY}/common-workflow-language"
    CROMWELL_BUILD_CWL_TEST_RESOURCES="${CROMWELL_BUILD_CWL_TEST_DIRECTORY}/v1.0/v1.0"
    CROMWELL_BUILD_CWL_TEST_WDL="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/cwl_conformance_test.wdl"
    CROMWELL_BUILD_CWL_TEST_INPUTS="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/cwl_conformance_test.inputs.json"
    CROMWELL_BUILD_CWL_TEST_OUTPUT="${CROMWELL_BUILD_LOG_DIRECTORY}/cwl_conformance_test.out.txt"

    # Setting CROMWELL_BUILD_CWL_TEST_PARALLELISM too high will cause false negatives due to cromwell server timeouts.
    case "${CROMWELL_BUILD_TYPE}" in
        conformanceTesk)
            # BA-6547: TESK is not currently tested in FC-Jenkins nor Travis
            CROMWELL_BUILD_CWL_RUNNER_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/ftp_centaur_cwl_runner.conf"
            CROMWELL_BUILD_CWL_TEST_PARALLELISM=8
            ;;
        *)
            CROMWELL_BUILD_CWL_RUNNER_CONFIG="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/centaur_cwl_runner_application.conf"
            CROMWELL_BUILD_CWL_TEST_PARALLELISM=10
            ;;
    esac

    export CROMWELL_BUILD_CWL_RUNNER_CONFIG
    export CROMWELL_BUILD_CWL_RUNNER_MODE
    export CROMWELL_BUILD_CWL_TOOL_VERSION
    export CROMWELL_BUILD_CWL_TEST_VERSION
    export CROMWELL_BUILD_CWL_TEST_COMMIT
    export CROMWELL_BUILD_CWL_TEST_RUNNER
    export CROMWELL_BUILD_CWL_TEST_DIRECTORY
    export CROMWELL_BUILD_CWL_TEST_RESOURCES
    export CROMWELL_BUILD_CWL_TEST_WDL
    export CROMWELL_BUILD_CWL_TEST_INPUTS
    export CROMWELL_BUILD_CWL_TEST_OUTPUT
    export CROMWELL_BUILD_CWL_TEST_PARALLELISM
}

cromwell::private::verify_secure_build() {
    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_TRAVIS}"|\
        "${CROMWELL_BUILD_PROVIDER_GITHUB}"|\
        "${CROMWELL_BUILD_PROVIDER_GOOGLE}"|\
        "${CROMWELL_BUILD_PROVIDER_CIRCLE}")
            if [[ "${CROMWELL_BUILD_IS_SECURE}" != "true" ]] && \
                [[ "${CROMWELL_BUILD_REQUIRES_SECURE}" == "true" ]]; then
                echo "********************************************************"
                echo "********************************************************"
                echo "**                                                    **"
                echo "**  WARNING: Encrypted keys are unavailable. Exiting. **"
                echo "**                                                    **"
                echo "********************************************************"
                echo "********************************************************"
                exit 0
            fi
            ;;
        *)
            ;;
    esac
}

cromwell::private::exec_test_script() {
    local upper_build_type
    upper_build_type="$(tr '[:lower:]' '[:upper:]' <<< "${CROMWELL_BUILD_TYPE:0:1}")${CROMWELL_BUILD_TYPE:1}"
    exec "${CROMWELL_BUILD_SCRIPTS_DIRECTORY}/test${upper_build_type}.sh"
}

cromwell::private::stop_travis_defaults() {
  # https://stackoverflow.com/questions/27382295/how-to-stop-services-on-travis-ci-running-by-default#answer-27410479
  sudo /etc/init.d/mysql stop || true
  sudo /etc/init.d/postgresql stop || true
}

cromwell::private::delete_boto_config() {
    # https://github.com/travis-ci/travis-ci/issues/7940#issuecomment-310759657
    sudo rm -f /etc/boto.cfg
    export BOTO_CONFIG=/dev/null
}

cromwell::private::delete_sbt_boot() {
    # Delete ~/.sbt/boot to fix consistent, almost immediate failures on sub-builds (usually TES but sometimes others).
    # Even purging Travis caches didn't always fix the problem. Fortunately stackoverflow knew what to do:
    # https://stackoverflow.com/questions/24539576/sbt-scala-2-10-4-missing-scala-tools-nsc-global
    rm -rf ~/.sbt/boot/
}

cromwell::private::update_apt_get() {
    sudo apt-get update
}

cromwell::private::install_unzip() {
    sudo apt-get install -y unzip
}

cromwell::private::install_python3() {
    sudo apt-get install -y python3-dev

    # set python as python3
    # https://manpages.ubuntu.com/manpages/focal/en/man1/update-alternatives.1.html#commands
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1

    # upgrade python dependencies
    # https://pip.pypa.io/en/stable/installing/#installing-with-get-pip-py
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python3 get-pip.py
    pip3 install --upgrade --force-reinstall pyopenssl
}

cromwell::private::install_adoptopenjdk() {
    # https://adoptopenjdk.net/installation.html#linux-pkg-deb
    sudo apt-get install -y wget apt-transport-https gnupg
    wget -qO - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public |
        sudo apt-key add -
    echo "deb https://adoptopenjdk.jfrog.io/adoptopenjdk/deb $(
            grep UBUNTU_CODENAME /etc/os-release | cut -d = -f 2
        ) main" |
        sudo tee /etc/apt/sources.list.d/adoptopenjdk.list
    sudo apt-get update
    sudo mkdir -p /usr/share/man/man1
    sudo apt-get install -y adoptopenjdk-11-hotspot
    sudo update-java-alternatives --set adoptopenjdk-11-hotspot-amd64
}

cromwell::private::install_sbt_launcher() {
    # Install sbt launcher
    # Non-deb package installation instructions adapted from
    # - https://github.com/sbt/sbt/releases/tag/v1.4.9
    # - https://github.com/broadinstitute/scala-baseimage/pull/4/files
    curl --location --fail --silent --show-error "https://github.com/sbt/sbt/releases/download/v1.4.9/sbt-1.4.9.tgz" |
        sudo tar zxf - -C /usr/share
    sudo update-alternatives --install /usr/bin/sbt sbt /usr/share/sbt/bin/sbt 1
}

cromwell::private::install_docker_compose() {
    # Install or upgrade docker-compose so that we get the correct exit codes
    # https://docs.docker.com/compose/release-notes/#1230
    # https://docs.docker.com/compose/install/
    curl \
        --location --fail --silent --show-error \
        "https://github.com/docker/compose/releases/download/1.28.5/docker-compose-$(uname -s)-$(uname -m)" \
        > docker-compose
    sudo mv docker-compose /usr/local/bin
    sudo chmod +x /usr/local/bin/docker-compose
}

cromwell::private::setup_pyenv_python_latest() {
    # Make `python` whatever the most recent version of python installed
    # Fixes cases where someone has set pyenv to override `python` to use an older `python2` instead of `python3`
    pyenv global "$(pyenv versions --bare --skip-aliases | sort -t '.' -k1,1n -k2,2n -k3,3n | tail -n 1)"
}

cromwell::private::pip_install() {
    local pip_package
    pip_package="${1:?pip_install called without a package}"; shift

    if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]]; then
        sudo -H "$(command -v pip3)" install "${pip_package}" "$@"
    elif [[ "${CROMWELL_BUILD_IS_VIRTUAL_ENV}" == "true" ]]; then
        pip3 install "${pip_package}" "$@"
    else
        pip3 install "${pip_package}" --user "$@"
    fi
}

cromwell::private::setup_travis_python() {
    export PATH="/opt/python/3.7.1/bin:${PATH}"
    cromwell::private::pip_install pip --upgrade
    cromwell::private::pip_install requests[security] --ignore-installed
}

cromwell::private::install_wait_for_it() {
    curl -s "${CROMWELL_BUILD_WAIT_FOR_IT_URL}" > "$CROMWELL_BUILD_WAIT_FOR_IT_SCRIPT"
    chmod +x "$CROMWELL_BUILD_WAIT_FOR_IT_SCRIPT"
}

cromwell::private::install_vault() {
    curl \
        --location --fail --silent --show-error \
        --output "${CROMWELL_BUILD_VAULT_ZIP}" \
        "https://releases.hashicorp.com/vault/1.6.3/vault_1.6.3_${CROMWELL_BUILD_OS}_amd64.zip"
    unzip "${CROMWELL_BUILD_VAULT_ZIP}" -d "$(dirname "${CROMWELL_BUILD_VAULT_EXECUTABLE}")"
}

cromwell::private::install_git_secrets() {
    # Only install git-secrets on CI. Users should have already installed the executable.
    if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]]; then
        git clone https://github.com/awslabs/git-secrets.git "${CROMWELL_BUILD_GIT_SECRETS_DIRECTORY}"
        pushd "${CROMWELL_BUILD_GIT_SECRETS_DIRECTORY}" > /dev/null
        git checkout "${CROMWELL_BUILD_GIT_SECRETS_COMMIT}"
        export PATH="${PATH}:${PWD}"
        popd > /dev/null
    fi
}

cromwell::private::install_minnie_kenny() {
    # Only install minnie-kenny on CI. Users should have already run the script themselves.
    if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]]; then
        pushd "${CROMWELL_BUILD_ROOT_DIRECTORY}" > /dev/null
        ./minnie-kenny.sh --force
        popd > /dev/null
    fi
}

cromwell::private::get_docker_name() {
    local docker_image
    docker_image="${1:?get_docker_name called without a docker image}"
    shift

    echo "${docker_image}_$$" | tr "/" "_" | tr ":" "-"
}

cromwell::private::start_docker() {
    local docker_image
    local docker_name
    local docker_cid_file
    docker_image="${1:?start_docker called without a docker image}"
    shift
    docker_name="$(cromwell::private::get_docker_name "${docker_image}")"
    docker_cid_file="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/${docker_name}.cid"

    docker run --name="${docker_name}" --cidfile="${docker_cid_file}" --detach "$@" "${docker_image}"
    docker logs --follow "${docker_name}" 2>&1 | sed "s/^/$(tput setaf 5)${docker_name}$(tput sgr0) /" &

    cromwell::private::add_exit_function docker rm --force --volumes "$(cat "${docker_cid_file}")"
    cromwell::private::add_exit_function rm "${docker_cid_file}"
}

cromwell::private::start_docker_mysql() {
    if cromwell::private::is_xtrace_enabled; then
        cromwell::private::exec_silent_function cromwell::private::start_docker_mysql "$@"

    else
        local docker_tag
        local docker_port
        docker_tag="${1?start_docker_mysql called without a docker_tag}"
        docker_port="${2?start_docker_mysql called without a docker_port}"
        shift 2
        cromwell::private::start_docker \
            mysql:"${docker_tag}" \
            --network="${CROMWELL_BUILD_DATABASE_NETWORK}" \
            --publish "${docker_port}":3306 \
            --env MYSQL_ROOT_PASSWORD=private \
            --env MYSQL_USER="${CROMWELL_BUILD_DATABASE_USERNAME}" \
            --env MYSQL_PASSWORD="${CROMWELL_BUILD_DATABASE_PASSWORD}" \
            --env MYSQL_DATABASE="${CROMWELL_BUILD_DATABASE_SCHEMA}" \
            --volume "${CROMWELL_BUILD_DOCKER_DIRECTORY}"/mysql-conf.d:/etc/mysql/conf.d \

    fi
}

cromwell::private::start_docker_mariadb() {
    if cromwell::private::is_xtrace_enabled; then
        cromwell::private::exec_silent_function cromwell::private::start_docker_mariadb "$@"

    else
        local docker_tag
        local docker_port
        docker_tag="${1?start_docker_mariadb called without a docker_tag}"
        docker_port="${2?start_docker_mariadb called without a docker_port}"
        shift 2
        cromwell::private::start_docker \
            mariadb:"${docker_tag}" \
            --network="${CROMWELL_BUILD_DATABASE_NETWORK}" \
            --publish "${docker_port}":3306 \
            --env MYSQL_ROOT_PASSWORD=private \
            --env MYSQL_USER="${CROMWELL_BUILD_DATABASE_USERNAME}" \
            --env MYSQL_PASSWORD="${CROMWELL_BUILD_DATABASE_PASSWORD}" \
            --env MYSQL_DATABASE="${CROMWELL_BUILD_DATABASE_SCHEMA}" \
            --volume "${CROMWELL_BUILD_DOCKER_DIRECTORY}"/mariadb-conf.d:/etc/mysql/conf.d \

    fi
}

cromwell::private::start_docker_postgresql() {
    if cromwell::private::is_xtrace_enabled; then
        cromwell::private::exec_silent_function cromwell::private::start_docker_postgresql "$@"

    else
        local docker_tag
        local docker_port
        docker_tag="${1?start_docker_postgresql called without a docker_tag}"
        docker_port="${2?start_docker_postgresql called without a docker_port}"
        shift 2
        cromwell::private::start_docker \
            postgres:"${docker_tag}" \
            --network="${CROMWELL_BUILD_DATABASE_NETWORK}" \
            --publish "${docker_port}":5432 \
            --env POSTGRES_USER="${CROMWELL_BUILD_DATABASE_USERNAME}" \
            --env POSTGRES_PASSWORD="${CROMWELL_BUILD_DATABASE_PASSWORD}" \
            --env POSTGRES_DB="${CROMWELL_BUILD_DATABASE_SCHEMA}" \
            --volume "${CROMWELL_BUILD_DOCKER_DIRECTORY}"/postgresql-initdb.d:/docker-entrypoint-initdb.d \

    fi
}

cromwell::private::start_docker_databases() {
    if [[ -n "${CROMWELL_BUILD_MYSQL_DOCKER_TAG:+set}" ]]; then
        cromwell::private::start_docker_mysql \
            "${CROMWELL_BUILD_MYSQL_DOCKER_TAG}" "${CROMWELL_BUILD_MYSQL_PORT}"
    fi
    if [[ -n "${CROMWELL_BUILD_MARIADB_DOCKER_TAG:+set}" ]]; then
        cromwell::private::start_docker_mariadb \
            "${CROMWELL_BUILD_MARIADB_DOCKER_TAG}" "${CROMWELL_BUILD_MARIADB_PORT}"
    fi
    if [[ -n "${CROMWELL_BUILD_POSTGRESQL_DOCKER_TAG:+set}" ]]; then
        cromwell::private::start_docker_postgresql \
            "${CROMWELL_BUILD_POSTGRESQL_DOCKER_TAG}" "${CROMWELL_BUILD_POSTGRESQL_PORT}"
    fi
}

cromwell::private::install_cwltest() {
    # TODO: No clue why these are needed for cwltool. If you know please update this comment.
    sudo apt-get install procps || true
    cromwell::private::pip_install cwltool=="${CROMWELL_BUILD_CWL_TOOL_VERSION}" --ignore-installed
    cromwell::private::pip_install cwltest=="${CROMWELL_BUILD_CWL_TEST_VERSION}"
}

cromwell::private::checkout_pinned_cwl() {
    if [[ ! -d "${CROMWELL_BUILD_CWL_TEST_DIRECTORY}" ]]; then
        git clone \
            https://github.com/common-workflow-language/common-workflow-language.git \
            "${CROMWELL_BUILD_CWL_TEST_DIRECTORY}"
        (
            pushd "${CROMWELL_BUILD_CWL_TEST_DIRECTORY}" > /dev/null
            git checkout "${CROMWELL_BUILD_CWL_TEST_COMMIT}"
            popd > /dev/null
        )
    fi
}

cromwell::private::write_cwl_test_inputs() {
    cat <<JSON >"${CROMWELL_BUILD_CWL_TEST_INPUTS}"
{
    "cwl_conformance_test.cwl_dir": "${CROMWELL_BUILD_CWL_TEST_DIRECTORY}",
    "cwl_conformance_test.test_result_output": "${CROMWELL_BUILD_CWL_TEST_OUTPUT}",
    "cwl_conformance_test.centaur_cwl_runner": "${CROMWELL_BUILD_CWL_TEST_RUNNER}",
    "cwl_conformance_test.conformance_expected_failures":
        "${CROMWELL_BUILD_RESOURCES_DIRECTORY}/${CROMWELL_BUILD_BACKEND_TYPE}_conformance_expected_failures.txt",
    "cwl_conformance_test.timeout": 2400
}
JSON
}

cromwell::private::vault_run() {
    if cromwell::private::is_xtrace_enabled; then
        cromwell::private::exec_silent_function cromwell::private::vault_run "$@"
    else
        # Run a vault executable that is NOT hosted inside of a docker.io image.
        # For those committers with vault access this avoids pull rate limits reported in BT-143.
        VAULT_ADDR=https://clotho.broadinstitute.org:8200 "${CROMWELL_BUILD_VAULT_EXECUTABLE}" "$@"
    fi
}

cromwell::private::login_vault() {
    if cromwell::private::is_xtrace_enabled; then
        cromwell::private::exec_silent_function cromwell::private::login_vault
    else
        local vault_token

        # shellcheck disable=SC2153
        if [[ -n "${VAULT_ROLE_ID:+set}" ]] && [[ -n "${VAULT_SECRET_ID:+set}" ]]; then
            vault_token="$(
                cromwell::private::vault_run \
                    write -field=token \
                    auth/approle/login role_id="${VAULT_ROLE_ID}" secret_id="${VAULT_SECRET_ID}"
            )"
        else
            vault_token="${VAULT_TOKEN:-}"
        fi

        if [[ -n "${vault_token}" ]]; then
            # Don't fail here if vault login fails
            # shellcheck disable=SC2015
            cromwell::private::vault_run \
                login "${vault_token}" < /dev/null > /dev/null \
                && echo vault login success \
                || true
        fi
    fi
}

cromwell::private::login_docker() {
    if cromwell::private::is_xtrace_enabled; then
        cromwell::private::exec_silent_function cromwell::private::login_docker
    else
        local docker_username
        local docker_password

        # Do not fail if docker login fails. We'll try to pull images anonymously.
        docker_username="$(
            cromwell::private::vault_run read -field=username secret/dsde/cromwell/common/cromwell-dockerhub || true
        )"
        docker_password="$(
            cromwell::private::vault_run read -field=password secret/dsde/cromwell/common/cromwell-dockerhub || true
        )"
        docker login --username "${docker_username}" --password-stdin <<< "${docker_password}" || true
    fi
}

cromwell::private::render_secure_resources() {
    # Avoid docker output to sbt's stderr by pulling the image here
    docker pull broadinstitute/dsde-toolbox:dev | cat
    # Copy the CI resources, then render the secure resources using Vault
    sbt -Dsbt.supershell=false --warn renderCiResources \
    || if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]]; then
        echo
        echo "Continuing without rendering secure resources."
    else
        echo
        echo "**************************************************************"
        echo "**************************************************************"
        echo "**                                                          **"
        echo "**        WARNING: Unable to render vault resources.        **"
        echo "**  '*.ctmpl' files should be copied and updated manually.  **"
        echo "**                                                          **"
        echo "**************************************************************"
        echo "**************************************************************"
    fi
}

cromwell::private::copy_all_resources() {
    # Only copy the CI resources. Secure resources are not rendered.
    sbt -Dsbt.supershell=false --warn copyCiResources
}

cromwell::private::setup_secure_resources() {
    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_JENKINS}")
            # Jenkins secret resources should have already been rendered outside the CI's docker-compose container.
            cromwell::private::copy_all_resources
            ;;
        *)
            cromwell::private::render_secure_resources
            ;;
    esac
}

cromwell::private::make_build_directories() {
    if [[ "${CROMWELL_BUILD_PROVIDER}" == "${CROMWELL_BUILD_PROVIDER_JENKINS}" ]]; then
        sudo chmod -R a+w .
    fi
    mkdir -p "${CROMWELL_BUILD_LOG_DIRECTORY}"
    mkdir -p "${CROMWELL_BUILD_RESOURCES_DIRECTORY}"
}

cromwell::private::find_cromwell_jar() {
    CROMWELL_BUILD_CROMWELL_JAR="$( \
        find "${CROMWELL_BUILD_ROOT_DIRECTORY}/server/target/scala-2.12" -name "cromwell-*.jar" -print0 \
        | xargs -0 ls -1 -t \
        | head -n 1 \
        2> /dev/null \
        || true)"
    export CROMWELL_BUILD_CROMWELL_JAR
}

cromwell::private::exists_cromwell_jar() {
    test -s "${CROMWELL_BUILD_CROMWELL_JAR}"
}

cromwell::private::assemble_jars() {
    # CROMWELL_BUILD_SBT_ASSEMBLY_COMMAND allows for an override of the default `assembly` command for assembly.
    # This can be useful to reduce time and memory that might otherwise be spent assembling unused subprojects.
    # shellcheck disable=SC2086
    CROMWELL_SBT_ASSEMBLY_LOG_LEVEL=error \
        sbt \
        -Dsbt.supershell=false \
        --warn \
        ${CROMWELL_BUILD_SBT_COVERAGE_COMMAND} \
        --error \
        ${CROMWELL_BUILD_SBT_ASSEMBLY_COMMAND}
}

cromwell::private::setup_prior_version_resources() {
    if [[ "${CROMWELL_BUILD_REQUIRES_PRIOR_VERSION}" == "true" ]]; then
        local prior_config
        local prior_jar
        prior_config="${CROMWELL_BUILD_CROMWELL_CONFIG/%_application.conf/_${CROMWELL_BUILD_PRIOR_VERSION_NUMBER}_application.conf}"
        prior_jar="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/cromwell_${CROMWELL_BUILD_PRIOR_VERSION_NUMBER}.jar"

        if [[ -f "${prior_config}" ]]; then
            CROMWELL_BUILD_PRE_RESTART_CROMWELL_CONFIG="${prior_config}"
        else
            CROMWELL_BUILD_PRE_RESTART_CROMWELL_CONFIG="${CROMWELL_BUILD_CROMWELL_CONFIG}"
        fi

        CROMWELL_BUILD_PRE_RESTART_DOCKER_TAG="${CROMWELL_BUILD_PRIOR_VERSION_NUMBER}"
        CROMWELL_BUILD_PRE_RESTART_CROMWELL_JAR="${prior_jar}"

        # Copy the prior versions jar out of the previously published docker image
        docker run \
            --rm \
            --entrypoint= \
            --volume "${CROMWELL_BUILD_RESOURCES_DIRECTORY}:${CROMWELL_BUILD_RESOURCES_DIRECTORY}" \
            broadinstitute/cromwell:"${CROMWELL_BUILD_PRE_RESTART_DOCKER_TAG}" \
            cp /app/cromwell.jar "${CROMWELL_BUILD_PRE_RESTART_CROMWELL_JAR}"
    else
        # In tests that are looking for a prior version, actually just use the current version
        CROMWELL_BUILD_PRE_RESTART_CROMWELL_CONFIG="${CROMWELL_BUILD_CROMWELL_CONFIG}"
        CROMWELL_BUILD_PRE_RESTART_DOCKER_TAG="${CROMWELL_BUILD_DOCKER_TAG}"
        CROMWELL_BUILD_PRE_RESTART_CROMWELL_JAR="${CROMWELL_BUILD_CROMWELL_JAR}"
    fi

    export CROMWELL_BUILD_PRE_RESTART_CROMWELL_CONFIG
    export CROMWELL_BUILD_PRE_RESTART_DOCKER_TAG
    export CROMWELL_BUILD_PRE_RESTART_CROMWELL_JAR
}

cromwell::private::generate_code_coverage() {
    sbt -Dsbt.supershell=false --warn coverageReport
    sbt -Dsbt.supershell=false --warn coverageAggregate
    bash <(curl -s https://codecov.io/bash) > /dev/null || true
}

cromwell::private::publish_artifacts_only() {
    CROMWELL_SBT_ASSEMBLY_LOG_LEVEL=warn sbt -Dsbt.supershell=false --warn "$@" publish
}

cromwell::private::publish_artifacts_and_docker() {
    CROMWELL_SBT_ASSEMBLY_LOG_LEVEL=warn sbt -Dsbt.supershell=false --warn "$@" publish dockerBuildAndPush
}

cromwell::private::publish_artifacts_check() {
    sbt -Dsbt.supershell=false --warn verifyArtifactoryCredentialsExist
}

# Some CI environments want to know when new docker images are published. They do not currently poll dockerhub but do
# poll github. To help those environments, signal that a new set of docker images has been published to dockerhub by
# updating a well known branch in github.
cromwell::private::push_publish_complete() {
    local github_private_deploy_key="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/github_private_deploy_key"
    local git_repo="git@github.com:broadinstitute/cromwell.git"
    local git_publish_branch="${CROMWELL_BUILD_BRANCH}_publish_complete"
    local git_publish_remote="publish_complete"
    local git_publish_message="publish complete [skip ci]"

    # Loosely adapted from https://github.com/broadinstitute/workbench-libs/blob/435a932/scripts/version_update.sh
    mkdir publish_complete
    pushd publish_complete > /dev/null

    git init
    git config core.sshCommand "ssh -i ${github_private_deploy_key} -F /dev/null"
    git config user.email "${CROMWELL_BUILD_GIT_USER_EMAIL}"
    git config user.name "${CROMWELL_BUILD_GIT_USER_NAME}"

    git remote add "${git_publish_remote}" "${git_repo}"
    git checkout -b "${git_publish_branch}"
    git commit --allow-empty -m "${git_publish_message}"
    git push -f "${git_publish_remote}" "${git_publish_branch}"

    popd > /dev/null
}

cromwell::private::start_build_heartbeat() {
    # Sleep one minute between printouts, but don't zombie forever
    for ((i=0; i < "${CROMWELL_BUILD_HEARTBEAT_MINUTES}"; i++)); do
        sleep 60
        # shellcheck disable=SC2059
        printf "${CROMWELL_BUILD_HEARTBEAT_PATTERN}"
    done &
    CROMWELL_BUILD_HEARTBEAT_PID=$!
    cromwell::private::add_exit_function cromwell::private::kill_build_heartbeat
}

cromwell::private::start_cromwell_log_tail() {
    while [[ ! -f "${CROMWELL_BUILD_CROMWELL_LOG}" ]]; do
        sleep 2
    done && tail -n 0 -f "${CROMWELL_BUILD_CROMWELL_LOG}" 2> /dev/null &
    CROMWELL_BUILD_CROMWELL_LOG_TAIL_PID=$!
    cromwell::private::add_exit_function cromwell::private::kill_cromwell_log_tail
}

cromwell::private::start_centaur_log_tail() {
    while [[ ! -f "${CROMWELL_BUILD_CENTAUR_LOG}" ]]; do
        sleep 2
    done && tail -n 0 -f "${CROMWELL_BUILD_CENTAUR_LOG}" 2> /dev/null &
    CROMWELL_BUILD_CENTAUR_LOG_TAIL_PID=$!
    cromwell::private::add_exit_function cromwell::private::kill_centaur_log_tail
}

cromwell::private::cat_centaur_log() {
    echo "CENTAUR LOG"
    cat "${CROMWELL_BUILD_CENTAUR_LOG}"
}

cromwell::private::cat_conformance_log() {
    echo "CONFORMANCE LOG"
    cat "${CROMWELL_BUILD_CWL_TEST_OUTPUT}"
}

cromwell::private::kill_build_heartbeat() {
    if [[ -n "${CROMWELL_BUILD_HEARTBEAT_PID:+set}" ]]; then
        cromwell::private::kill_tree "${CROMWELL_BUILD_HEARTBEAT_PID}"
    fi
}

cromwell::private::kill_cromwell_log_tail() {
    if [[ -n "${CROMWELL_BUILD_CROMWELL_LOG_TAIL_PID:+set}" ]]; then
        cromwell::private::kill_tree "${CROMWELL_BUILD_CROMWELL_LOG_TAIL_PID}"
    fi
}

cromwell::private::kill_centaur_log_tail() {
    if [[ -n "${CROMWELL_BUILD_CENTAUR_LOG_TAIL_PID:+set}" ]]; then
        cromwell::private::kill_tree ${CROMWELL_BUILD_CENTAUR_LOG_TAIL_PID}
    fi
}

cromwell::private::run_exit_functions() {
    if [[ -f "${CROMWELL_BUILD_EXIT_FUNCTIONS}" ]]; then
        local exit_function
        while read -r exit_function; do
          ${exit_function} || true
        done < "${CROMWELL_BUILD_EXIT_FUNCTIONS}"
        rm "${CROMWELL_BUILD_EXIT_FUNCTIONS}" || true
    fi
}

# Adds the function to the list of functions to run on exit.
# Requires at least one positional parameter, the function to run.
cromwell::private::add_exit_function() {
    if [[ "$#" -eq 0 ]]; then
        echo "Error: add_exit_function called without a function" >&2
        exit 1
    fi
    echo "$@" >> "${CROMWELL_BUILD_EXIT_FUNCTIONS}"
    trap cromwell::private::run_exit_functions TERM EXIT
}

cromwell::private::exec_silent_function() {
    local silent_function
    local xtrace_restore_function
    silent_function="${1:?exec_silent_function called without a function}"; shift

    xtrace_restore_function="$(shopt -po xtrace || true)"
    shopt -uo xtrace
    ${silent_function} "$@"
    ${xtrace_restore_function}
}

cromwell::private::is_xtrace_enabled() {
    # Return 0 if xtrace is disabled (set +x), 1 if xtrace is enabled (set -x).
    shopt -qo xtrace
}

cromwell::private::kill_tree() {
  local pid
  local cpid
  pid="${1:?kill_tree called without a pid}"; shift
  for cpid in $(pgrep -P "${pid}"); do
    cromwell::private::kill_tree "${cpid}"
  done
  kill "${pid}" 2> /dev/null
}

cromwell::private::start_conformance_cromwell() {
    # Start the Cromwell server in the directory containing input files so it can access them via their relative path
    pushd "${CROMWELL_BUILD_CWL_TEST_RESOURCES}" > /dev/null

    # Turn off call caching as hashing doesn't work since it sees local and not GCS paths.
    # CWL conformance uses alpine images that do not have bash.
    java \
        -Xmx2g \
        -Dconfig.file="${CROMWELL_BUILD_CROMWELL_CONFIG}" \
        -Dcall-caching.enabled=false \
        -Dsystem.job-shell=/bin/sh \
        -jar "${CROMWELL_BUILD_CROMWELL_JAR}" \
        server &

    CROMWELL_BUILD_CONFORMANCE_CROMWELL_PID=$!

    popd > /dev/null

    cromwell::private::add_exit_function cromwell::private::kill_conformance_cromwell
}

cromwell::private::kill_conformance_cromwell() {
    if [[ -n "${CROMWELL_BUILD_CONFORMANCE_CROMWELL_PID+set}" ]]; then
        cromwell::build::kill_tree "${CROMWELL_BUILD_CONFORMANCE_CROMWELL_PID}"
    fi
}

cromwell::private::run_conformance_wdl() {
    pushd "${CROMWELL_BUILD_CWL_TEST_RESOURCES}" > /dev/null

    CENTAUR_CWL_JAVA_ARGS="-Dconfig.file=${CROMWELL_BUILD_CWL_RUNNER_CONFIG}" \
        java \
        -Xmx6g \
        -Dbackend.providers.Local.config.concurrent-job-limit="${CROMWELL_BUILD_CWL_TEST_PARALLELISM}" \
        -jar "${CROMWELL_BUILD_CROMWELL_JAR}" \
        run "${CROMWELL_BUILD_CWL_TEST_WDL}" \
        -i "${CROMWELL_BUILD_CWL_TEST_INPUTS}"

    popd > /dev/null
}

cromwell::build::exec_test_script() {
    cromwell::private::create_build_variables
    if [[ "${CROMWELL_BUILD_RUN_TESTS}" == "false" ]]; then
      echo "Use '[force ci]' in commit message to run tests on 'push'"
      exit 0
    fi
    cromwell::private::exec_test_script
}

cromwell::build::setup_common_environment() {
    cromwell::private::check_debug
    cromwell::private::create_build_variables
    cromwell::private::echo_build_variables
    cromwell::private::verify_secure_build
    cromwell::private::make_build_directories
    cromwell::private::install_git_secrets
    cromwell::private::install_minnie_kenny
    cromwell::private::install_wait_for_it
    cromwell::private::create_database_variables

    case "${CROMWELL_BUILD_PROVIDER}" in
        "${CROMWELL_BUILD_PROVIDER_TRAVIS}")
            cromwell::private::stop_travis_defaults
            # Try to login to vault, and if successful then use vault creds to login to docker.
            # For those committers with vault access this avoids pull rate limits reported in BT-143.
            cromwell::private::install_vault
            cromwell::private::login_vault
            cromwell::private::login_docker
            cromwell::private::install_adoptopenjdk
            cromwell::private::install_sbt_launcher
            cromwell::private::install_docker_compose
            cromwell::private::delete_boto_config
            cromwell::private::delete_sbt_boot
            cromwell::private::upgrade_pip
            cromwell::private::start_docker_databases
            ;;
        "${CROMWELL_BUILD_PROVIDER_GITHUB}")
            cromwell::private::update_apt_get
            cromwell::private::install_unzip
            # Try to login to vault, and if successful then use vault creds to login to docker.
            # For those committers with vault access this avoids pull rate limits reported in BT-143.
            cromwell::private::install_vault
            cromwell::private::login_vault
            cromwell::private::login_docker
            cromwell::private::install_adoptopenjdk
            cromwell::private::install_sbt_launcher
            cromwell::private::install_docker_compose
            cromwell::private::install_python3
            cromwell::private::start_docker_databases
            ;;
        "${CROMWELL_BUILD_PROVIDER_GOOGLE}"|\
        "${CROMWELL_BUILD_PROVIDER_CIRCLE}")
            # Try to login to vault, and if successful then use vault creds to login to docker.
            # For those committers with vault access this avoids pull rate limits reported in BT-143.
            cromwell::private::install_vault
            cromwell::private::login_vault
            cromwell::private::login_docker
            cromwell::private::install_adoptopenjdk
            cromwell::private::setup_pyenv_python_latest
            cromwell::private::start_docker_databases
            ;;
        "${CROMWELL_BUILD_PROVIDER_JENKINS}"|\
        *)
            ;;
    esac

    cromwell::private::setup_secure_resources
    cromwell::private::start_build_heartbeat
}


cromwell::build::setup_centaur_environment() {
    cromwell::private::create_centaur_variables
    cromwell::private::start_cromwell_log_tail
    cromwell::private::start_centaur_log_tail
    if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]]; then
        cromwell::private::add_exit_function cromwell::private::cat_centaur_log
    fi
}

cromwell::build::setup_conformance_environment() {
    cromwell::private::create_centaur_variables
    cromwell::private::create_conformance_variables
    if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]]; then
        cromwell::private::install_cwltest
    fi
    cromwell::private::checkout_pinned_cwl
    cromwell::private::write_cwl_test_inputs
    cromwell::private::add_exit_function cromwell::private::cat_conformance_log
}

cromwell::private::find_or_assemble_cromwell_jar() {
    cromwell::private::find_cromwell_jar
    if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]] || ! cromwell::private::exists_cromwell_jar; then
        echo "Please wait, building jars…"
        cromwell::private::assemble_jars
    fi
    cromwell::private::find_cromwell_jar
    if ! cromwell::private::exists_cromwell_jar; then
        echo "Error: find_or_assemble_cromwell_jar did not locate a cromwell jar even after assembly" >&2
        exit 1
    fi
}

cromwell::build::assemble_jars() {
    cromwell::private::find_or_assemble_cromwell_jar
    cromwell::private::setup_prior_version_resources
}

cromwell::build::build_docker_image() {
    local executable_name
    local docker_image
    executable_name="${1:?build_docker_image called without a executable_name}"
    docker_image="${2:?build_docker_image called without a docker_image}"
    shift
    shift

    if [[ "${CROMWELL_BUILD_IS_CI}" == "true" ]] || ! docker image ls --quiet "${docker_image}" | grep .; then
        echo "Please wait, building ${executable_name} into ${docker_image}…"

        sbt \
            --error \
            "set \`${executable_name}\`/docker/imageNames := List(ImageName(\"${docker_image}\"))" \
            "${executable_name}/docker"
    fi
}

cromwell::build::build_cromwell_docker() {
    cromwell::build::build_docker_image server broadinstitute/cromwell:"${CROMWELL_BUILD_DOCKER_TAG}"
}

cromwell:build::run_sbt_test() {
    # CROMWELL_BUILD_SBT_COVERAGE_COMMAND allows enabling or disabling `sbt coverage`.
    # Note: sbt logging level now affects the test logging level: https://github.com/sbt/sbt/issues/4480
    # Globally leaving the sbt log level at info for now.
    # Disabling the supershell to reduce log levels.
    # Splitting the JVMs for compilation then scalatest-with-cromwell to reduce memory pressure.
    # Splitting the JVMs for testing-by-sbt-project to also reduce memory pressure.
    # The list of sbt projects is generated by parsing this `log.info()` output, with log color formatting turned off:
    # https://github.com/sbt/sbt/blob/v1.4.9/main/src/main/scala/sbt/Main.scala#L759-L760
    # For more information on testing and memory see also: https://olegych.github.io/blog/sbt-fork.html

    # shellcheck disable=SC2086
    sbt \
        -Dsbt.supershell=false \
        ${CROMWELL_BUILD_SBT_COVERAGE_COMMAND} \
        test:compile

    local sbt_tests

    if [[ -n "${CROMWELL_BUILD_SBT_INCLUDE}" ]]; then
        # Test only the projects specified
        sbt_tests=$(
            sbt -Dsbt.log.noformat=true projects |
                grep -F $'[info] \t   ' |
                awk '{print $2}' |
                grep -E "^(${CROMWELL_BUILD_SBT_INCLUDE})$" |
                awk '{printf "%s/test ", $1}' \
                || true
        )
    elif [[ -n "${CROMWELL_BUILD_SBT_EXCLUDE}" ]]; then
        # Test all the projects except a few exclusions
        sbt_tests=$(
            sbt -Dsbt.log.noformat=true projects |
                grep -F $'[info] \t   ' |
                awk '{print $2}' |
                grep -v -E "^(${CROMWELL_BUILD_SBT_EXCLUDE})$" |
                awk '{printf "%s/test ", $1}' \
                || true
        )
    else
        # Test all the projects
        sbt_tests="test"
    fi

    # Ensure we are testing something
    if [[ -z "${sbt_tests}" ]]; then
        echo "Error: Unable to retrieve list of sbt projects." >&2
        echo "CROMWELL_BUILD_SBT_INCLUDE='${CROMWELL_BUILD_SBT_INCLUDE}'" >&2
        echo "CROMWELL_BUILD_SBT_EXCLUDE='${CROMWELL_BUILD_SBT_EXCLUDE}'" >&2
        exit 1
    fi

    echo "Starting sbt ${sbt_tests}"
    # shellcheck disable=SC2086
    sbt \
        -Dsbt.supershell=false \
        -Dakka.test.timefactor=${CROMWELL_BUILD_UNIT_SPAN_SCALE_FACTOR} \
        -Dbackend.providers.Local.config.filesystems.local.localization.0=copy \
        ${CROMWELL_BUILD_SBT_COVERAGE_COMMAND} \
        ${sbt_tests}
}

cromwell::build::run_centaur() {
    local -a additional_args
    additional_args=()
    if [[ -n "${CROMWELL_BUILD_CENTAUR_TEST_ADDITIONAL_PARAMETERS-}" ]]; then
        # Allow splitting on space to simulate an exported array
        # https://stackoverflow.com/questions/5564418/exporting-an-array-in-bash-script#answer-5564589
        # shellcheck disable=SC2206
        additional_args=(${CROMWELL_BUILD_CENTAUR_TEST_ADDITIONAL_PARAMETERS})
    fi
    if [[ "${CROMWELL_BUILD_GENERATE_COVERAGE}" == "true" ]]; then
        additional_args+=("-g")
    fi
    # Handle empty arrays in older versions of bash
    # https://stackoverflow.com/questions/7577052/bash-empty-array-expansion-with-set-u#answer-7577209
    "${CROMWELL_BUILD_ROOT_DIRECTORY}/centaur/test_cromwell.sh" \
        -n "${CROMWELL_BUILD_CENTAUR_CONFIG}" \
        -l "${CROMWELL_BUILD_LOG_DIRECTORY}" \
        ${additional_args[@]+"${additional_args[@]}"} \
        "$@"
}

cromwell::build::run_conformance() {
    cromwell::private::start_conformance_cromwell

    # Give cromwell time to start up
    sleep 30

    cromwell::private::run_conformance_wdl
}

cromwell::build::generate_code_coverage() {
    if [[ "${CROMWELL_BUILD_GENERATE_COVERAGE}" == "true" ]]; then
        cromwell::private::generate_code_coverage
    fi
}

cromwell::build::check_published_artifacts() {
    if [[ "${CROMWELL_BUILD_PROVIDER}" == "${CROMWELL_BUILD_PROVIDER_TRAVIS}" ]] && \
        [[ "${CROMWELL_BUILD_TYPE}" == "sbt" ]] && \
        [[ "${CROMWELL_BUILD_SBT_INCLUDE}" == "" ]] && \
        [[ "${CROMWELL_BUILD_EVENT}" == "push" ]]; then

        if [[ "${CROMWELL_BUILD_BRANCH}" == "develop" ]] || \
            [[ "${CROMWELL_BUILD_BRANCH}" =~ ^[0-9\.]+_hotfix$ ]] || \
            [[ -n "${CROMWELL_BUILD_TAG:+set}" ]]; then
            # If cromwell::build::publish_artifacts is going to be publishing later check now that it will work
            sbt \
                -Dsbt.supershell=false \
                --error \
                errorIfAlreadyPublished
        fi

    fi
}

cromwell::build::publish_artifacts() {
    if [[ "${CROMWELL_BUILD_PROVIDER}" == "${CROMWELL_BUILD_PROVIDER_TRAVIS}" ]] && \
        [[ "${CROMWELL_BUILD_TYPE}" == "sbt" ]] && \
        [[ "${CROMWELL_BUILD_SBT_INCLUDE}" == "" ]] && \
        [[ "${CROMWELL_BUILD_EVENT}" == "push" ]]; then

        if [[ "${CROMWELL_BUILD_BRANCH}" == "develop" ]]; then
            # Publish images for both the "cromwell develop branch" and the "cromwell dev environment".
            CROMWELL_SBT_DOCKER_TAGS=develop,dev \
                cromwell::private::publish_artifacts_and_docker \
                -Dproject.isSnapshot=true
            cromwell::private::push_publish_complete

        elif [[ "${CROMWELL_BUILD_BRANCH}" =~ ^[0-9\.]+_hotfix$ ]]; then
            # Docker tags float. "30" is the latest hotfix. Those dockers are published here on each hotfix commit.
            cromwell::private::publish_artifacts_and_docker -Dproject.isSnapshot=false

        elif [[ -n "${CROMWELL_BUILD_TAG:+set}" ]]; then
            # Artifact tags are static. Once "30" is set that is only "30" forever. Those artifacts are published here.
            cromwell::private::publish_artifacts_only \
                -Dproject.version="${CROMWELL_BUILD_TAG}" \
                -Dproject.isSnapshot=false

        elif [[ "${CROMWELL_BUILD_IS_SECURE}" == "true" ]]; then
            cromwell::private::publish_artifacts_check

        fi

    fi
}

cromwell::build::exec_retry_function() {
    local retried_function
    local retry_count
    local attempt
    local exit_status

    retried_function="${1:?exec_retry_function called without a function}"; shift
    retry_count="${1:-3}"; shift || true
    sleep_seconds="${1:-15}"; shift || true

    # https://unix.stackexchange.com/a/82610
    # https://stackoverflow.com/a/17336953
    for attempt in $(seq 0 "${retry_count}"); do
        [[ ${attempt} -gt 0 ]] && sleep "${sleep_seconds}"
        ${retried_function} && exit_status=0 && break || exit_status=$?
    done
    return ${exit_status}
}

cromwell::build::exec_silent_function() {
    local silent_function
    silent_function="${1:?exec_silent_function called without a function}"; shift
    if cromwell::private::is_xtrace_enabled; then
        cromwell::private::exec_silent_function "${silent_function}" "$@"
    else
        ${silent_function} "$@"
    fi
}

cromwell::build::pip_install() {
    cromwell::private::pip_install "$@"
}

cromwell::build::add_exit_function() {
    cromwell::private::add_exit_function "$1"
}

cromwell::build::delete_docker_images() {
    local docker_delete_function
    local docker_image_file
    docker_delete_function="${1:?delete_images called without a docker_delete_function}"
    docker_image_file="${2:?delete_images called without a docker_image_file}"
    shift
    shift

    if [[ -f "${docker_image_file}" ]]; then
        local docker_image
        while read -r docker_image; do
          ${docker_delete_function} "${docker_image}" || true
        done < "${docker_image_file}"
        rm "${docker_image_file}" || true
    fi
}

cromwell::build::kill_tree() {
    cromwell::private::kill_tree "$1"
}
