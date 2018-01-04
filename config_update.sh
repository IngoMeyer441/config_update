#!/bin/bash

CONFIG_UPDATE_ROOT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
CONFIG_UPDATE_VERSION=( "0" "0" "0" )

BOLD_LIGHT_RED='\033[91;1m'
BOLD_LIGHT_GREEN='\033[92;1m'
BOLD_LIGHT_BLUE='\033[94;1m'
BOLD_LIGHT_MAGENTA='\033[95;1m'
BOLD_LIGHT_CYAN='\033[96;1m'
NC='\033[0m'


config-update () {
    local return_code

    abspath () {
        echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    }

    write_prompt_script () {
        local temp_prompt_directory

        temp_prompt_directory="$(mktemp -d)"
        [[ -n "${temp_prompt_directory}" ]] || return 1
        cat <<- EOF > "${temp_prompt_directory}/prompt.py"
			#!/usr/bin/env python
			# -*- coding: utf-8 -*-
			from __future__ import absolute_import
			from __future__ import division
			from __future__ import print_function
			from __future__ import unicode_literals
			import readline
			import sys
			PY2 = (sys.version_info.major < 3)
			if PY2:
			    input = raw_input
			def make_completer(vocabulary):
			    def custom_complete(text, state):
			        results = [x for x in vocabulary if x.startswith(text)] + [None]
			        return results[state] + " "
			    return custom_complete
			def main():
			    vocabulary = sys.argv[1:]
			    if not vocabulary:
			        print('You need at least one keyword for completion.', file=sys.stderr)
			        sys.exit(2)
			    readline.parse_and_bind('set show-all-if-ambiguous on')
			    readline.parse_and_bind('tab: menu-complete')
			    readline.set_completer(make_completer(vocabulary))
			    try:
			        stdout_backup = sys.stdout
			        sys.stdout = sys.stderr
			        result = input('> ').strip()
			        sys.stdout = stdout_backup
			        print(result)
			    except (EOFError, KeyboardInterrupt):
			        sys.exit(1)
			if __name__ == '__main__':
			    main()
		EOF
        [[ "$?" -eq 0 ]] || return 1
        chmod +x "${temp_prompt_directory}/prompt.py" || return 1
        echo "${temp_prompt_directory}/prompt.py"
    }

    init_variables () {
        if [[ -z "${CONFIG_UPDATE_CONFIG_ROOT_DIR}" ]]; then
            CONFIG_UPDATE_CONFIG_ROOT_DIR="${CONFIG_UPDATE_ROOT_DIR}"
        fi
        CONFIGS_DIR="${CONFIG_UPDATE_CONFIG_ROOT_DIR}/configs"
        CONFIGS_WORKING_DIR="${CONFIG_UPDATE_CONFIG_ROOT_DIR}/configs_working_directory"
        CONFIGS_LOCATION_FILE="${CONFIGS_WORKING_DIR}/.config_locations"
        SHOW_HELP=0
        SHOW_VERSION=0
        while [[ "$1" =~ ^-.* ]]; do
            case $1 in
                -h|--help)
                    SHOW_HELP=1
                    ;;
                --version)
                    SHOW_VERSION=1
                    ;;
                *)
                    echo "Ignoring unkown option '$1'."
            esac
            shift
        done
        if [[ "$1" = "" && (! -d "${CONFIGS_DIR}" || \
              "$(cd "${CONFIGS_DIR}" && git ls-files --modified)" = "") ]]; then
            FETCH_REMOTE_ONLY=1
        else
            FETCH_REMOTE_ONLY=0
            CONFIG_FILENAME="$1"
            EDIT_BRANCH="$2"
            if [[ -z "${EDIT_BRANCH}" ]]; then
                EDIT_BRANCH="master"
            fi
        fi
        CREATED_EDIT_BRANCH=0  # Can be set to `1` in `create_working_copy_and_fetch_remote_configs`
        [[ -z "${VISUAL}" ]] && VISUAL="vim"

        return 0
    }

    show_help () {
        echo "config-update - Manage your config files and their differences between multiple hosts"
        echo
        echo "Usage: config-update [-h | --help | --version] [config-file [branch]]"
        echo
        echo "optional arguments:"
        echo " -h, --help   show this help message and exit"
        echo " --version    print the version number and exit"
        echo
        echo "positional arguments:"
        echo " config-file  conig file (Git name) you want to alter"
        echo " branch       branch you want to update (default: master)"
    }

    show_version () {
        (IFS='.'; echo "config-update v${CONFIG_UPDATE_VERSION[*]}")
    }

    create_working_copy_and_fetch_remote_configs () {
        local return_code fetched_only ref local_branch local_branches remote_branch branches_to_verify
        local prompt_script_path base_branch

        [[ "${CONFIG_UPDATE_CONFIGS_REPO_URL}" != "" ]] || \
            { ERROR_OUTPUT="The variable ${BOLD_LIGHT_MAGENTA}CONFIG_UPDATE_CONFIGS_REPO_URL${NC} is not set."; \
              return 2; }
        [[ "${CONFIG_UPDATE_BRANCH}" != "" ]] || \
            { ERROR_OUTPUT="The variable ${BOLD_LIGHT_MAGENTA}CONFIG_UPDATE_BRANCH${NC} is not set."; return 3; }

        # Create a working copy of the configs directory that can be modified safely
        if [[ -d "${CONFIGS_DIR}" ]]; then
            rm -rf "${CONFIGS_WORKING_DIR}" && \
            cp -r "${CONFIGS_DIR}" "${CONFIGS_WORKING_DIR}"
            [[ "$?" -eq 0 ]] || { ERROR_OUTPUT="Could not create a working copy of the config directory."; return 4; }
        fi

        # Fetch remote changes
        if [[ "$(cd "${CONFIGS_WORKING_DIR}" 2>/dev/null && \
          git remote -v | awk '$1 == "origin" && $3 == "(fetch)" { print $2 }')" == \
          "${CONFIG_UPDATE_CONFIGS_REPO_URL}" ]]; then
            pushd "${CONFIGS_WORKING_DIR}" >/dev/null 2>&1 && \
            git fetch origin >/dev/null 2>&1 && \
            git remote prune origin
            return_code="$?"
            fetched_only=1
        else
            rm -rf "${CONFIGS_WORKING_DIR}" && \
            git clone "${CONFIG_UPDATE_CONFIGS_REPO_URL}" "${CONFIGS_WORKING_DIR}" >/dev/null 2>&1 && \
            pushd "${CONFIGS_WORKING_DIR}" >/dev/null 2>&1 && \
            git config push.default matching  # a simple `git push` synchronizes all branches
            return_code="$?"
            fetched_only=0
        fi
        [[ "${return_code}" -eq 0 ]] || { ERROR_OUTPUT="Could not fetch remote changes."; return 5; }

        # Guarantee that all remote branches are checked out as local tracking branches
        if [[ "${return_code}" -eq 0 ]]; then
            for ref in $(git for-each-ref --format='%(refname)' refs/remotes/origin/); do
                [[ "${ref}" != "refs/remotes/origin/HEAD" ]] || continue
                local_branch="$(echo "${ref}" | awk -F'/' '{ print $NF }')" && \
                remote_branch="origin/${local_branch}" && \
                git update-ref "refs/heads/${local_branch}" "${ref}" && \
                git branch --set-upstream-to "${remote_branch}" "${local_branch}" >/dev/null 2>&1
                return_code="$?"
                [[ "${return_code}" -eq 0 ]] || break
            done
        fi
        [[ "${return_code}" -eq 0 ]] || \
            { ERROR_OUTPUT="Could not setup config branches as local tracking branches."; return 6; }

        # Verify that required refs (`master`, `${CONFIG_UPDATE_BRANCH}` and `${EDIT_BRANCH}`) exist
        if [[ "${return_code}" -eq 0 ]]; then
            local_branches=()
            for ref in $(git for-each-ref --format='%(refname)' refs/heads/); do
                [[ "${ref}" != "refs/heads/HEAD" ]] || continue
                local_branch="$(echo "${ref}" | awk -F'/' '{ print $NF }')" && \
                local_branches+=( "${local_branch}" )
            done
            branches_to_verify=( "master" "${CONFIG_UPDATE_BRANCH}" )
            if [[ -n "${EDIT_BRANCH}" ]]; then
                branches_to_verify+=( "${EDIT_BRANCH}" )
            fi
            for local_branch in "${branches_to_verify[@]}"; do
                git show-ref --quiet --verify "refs/heads/${local_branch}"
                return_code="$?"
                if [[ "${return_code}" -ne 0 ]]; then
                    [[ "${local_branch}" != "master" ]] || \
                        { ERROR_OUTPUT="Local branch ${BOLD_LIGHT_CYAN}${local_branch}${NC} is missing."; break; }
                    echo -e "The required branch ${BOLD_LIGHT_CYAN}${local_branch}${NC} does not exist." \
                        "On which ${BOLD_LIGHT_GREEN}branch${NC} should it be based on?\n (tab completion is enabled)"
                    prompt_script_path="$(write_prompt_script)"
                    return_code="$?"
                    [[ "${return_code}" -eq 0 ]] || \
                        { ERROR_OUTPUT="Internal error, could not create temporary script file."; break; }
                    while true; do
                        base_branch="$("${prompt_script_path}" "${local_branches[@]}")" || return 7
                        git show-ref --quiet --verify "refs/heads/${base_branch}" && break
                        echo -e "The branch ${BOLD_LIGHT_CYAN}${base_branch}${NC} does not exist." \
                            "Please correct your input:"
                    done
                    rm -rf "$(dirname "${prompt_script_path}")"
                    git update-ref "refs/heads/${local_branch}" "refs/heads/${base_branch}" && \
                    git push -u origin "${local_branch}"
                    return_code="$?"
                    [[ "${return_code}" -eq 0 ]] || \
                        { ERROR_OUTPUT="Could not create a new branch ${BOLD_LIGHT_CYAN}${local_branch}${NC}"; break; }
                    if [[ "${local_branch}" = "${EDIT_BRANCH}" ]]; then
                        CREATED_EDIT_BRANCH=1
                    fi
                fi
            done
        fi
        [[ "${return_code}" -eq 0 ]] || return 7

        # Show diff stats if the local repository existed before
        if (( fetched_only )); then
            git diff --stat "HEAD@{1}" "HEAD"
        fi

        echo "Set up a working copy of the config directory and fetched remote changes."
        return 0
    }

    add_config () {
        local found_config locations location config_name config_filepath

        found_config=0
        if [[ -f "${CONFIGS_LOCATION_FILE}" ]]; then
            IFS=$'\n' read -d '' -r -a locations < "${CONFIGS_LOCATION_FILE}"
            for location in "${locations[@]}"; do
                config_name="$(echo "${location}" | cut -d: -f1)"
                if [[ "${config_name}" = "${CONFIG_FILENAME}" ]]; then
                    found_config=1
                    break
                fi
            done
        fi
        (( found_config )) && return 0
        echo -e "'${CONFIG_FILENAME}' is a new config file." \
            "Please specify the ${BOLD_LIGHT_GREEN}config filepath${NC}:\n" \
            "(absolute or relative to ~; tab completion is enabled)"
        pushd "${HOME}" >/dev/null 2>&1
        while true; do
            read -e -p '> ' -i "${config_filepath}" config_filepath
            [[ "$?" -eq 0 ]] || { popd >/dev/null 2>&1; return 8; }
            [[ -f "${config_filepath}" ]] && break
            echo -e "The file ${BOLD_LIGHT_BLUE}${config_filepath}${NC} does not exist. Please correct your input:"
        done
        config_filepath="$(abspath "${config_filepath}")"
        popd >/dev/null 2>&1
        mkdir -p "$(dirname "${CONFIG_FILENAME}")" || \
            { ERROR_OUTPUT="The directory ${BOLD_LIGHT_BLUE}$(dirname "${CONFIG_FILENAME}")${NC} could not be created."; \
              return 9; }
        cp "${config_filepath}" "${CONFIG_FILENAME}" || \
            { ERROR_OUTPUT="The config file ${BOLD_LIGHT_BLUE}${config_filepath}${NC} could not be copied into the repository."; \
              return 10; }
        echo "${CONFIG_FILENAME}:${config_filepath}" >> "${CONFIGS_LOCATION_FILE}" && \
        git add -f "${CONFIGS_LOCATION_FILE}"
        [[ "$?" -eq 0 ]] || \
            { ERROR_OUTPUT="${BOLD_LIGHT_BLUE}${CONFIG_FILENAME}${NC} could not be added to the locations file."; \
              return 11; }

        echo -e "Added the config file ${BOLD_LIGHT_BLUE}${config_filepath}${NC} to the repository."
        return 0
    }

    edit_config () {
        [[ -z "${CONFIG_FILENAME}" ]] && return 0
        git checkout "${EDIT_BRANCH}" >/dev/null 2>&1 || \
            { ERROR_OUTPUT="The branch ${BOLD_LIGHT_CYAN}${EDIT_BRANCH}${NC} that should be updated cannot be checked out."; \
              return 12; }
        [[ -d "$(dirname "${CONFIG_FILENAME}")" ]] || mkdir -p "$(dirname "${CONFIG_FILENAME}")" || \
            { ERROR_OUTPUT="The directory ${BOLD_LIGHT_BLUE}$(dirname "${CONFIG_FILENAME}")${NC} cannot be created."; \
              return 13; }
        ${VISUAL} "${CONFIG_FILENAME}" || { ERROR_OUTPUT="Your editor exited with a non-zero exit code."; return 14; }
        git add -f "${CONFIG_FILENAME}" && \
        git commit || { ERROR_OUTPUT="Could not commit changes."; return 15; }

        echo -e "Committed changes to ${BOLD_LIGHT_BLUE}${CONFIG_FILENAME}${NC}."
        return 0
    }

    merge_config () {
        merge_config_recursive () {
            local ref potential_closest_descendant descendant is_closest_descendant
            local descendants=()
            local closest_descendants=()
            local base_branch="$1"

            # Find all descendants and closest descendants of the given `base_branch`
            for ref in $(git for-each-ref --format='%(refname)' refs/heads/); do
                if [[ "${ref}" != "refs/heads/HEAD" ]] && \
                  git merge-base --is-ancestor "${base_branch}~" "${ref}" && \
                  [[ "$(git rev-parse "${base_branch}~")" != "$(git rev-parse "${ref}")" ]] && \
                  [[ "$(git rev-parse "${base_branch}")" != "$(git rev-parse "${ref}")" ]]; then
                    descendants+=( "${ref#refs/heads/}" )
                fi;
            done
            for potential_closest_descendant in "${descendants[@]}"; do
                is_closest_descendant=1
                for descendant in "${descendants[@]}"; do
                    if git merge-base --is-ancestor "${descendant}" "${potential_closest_descendant}" && \
                      [[ "$(git rev-parse "${potential_closest_descendant}")" != "$(git rev-parse "${descendant}")" ]];
                    then
                        is_closest_descendant=0
                        break
                    fi
                done
                if (( is_closest_descendant )); then
                    closest_descendants+=( "${potential_closest_descendant}" )
                fi
            done

            # Merge committed changes of the base branch into the closest descendants recursively
            # -> The change (commit) is propagated step by step
            for descendant in "${closest_descendants[@]}"; do
                git checkout "${descendant}" >/dev/null 2>&1 || \
                    { ERROR_OUTPUT="Could not check out ${BOLD_LIGHT_CYAN}${descendant}${NC} for merging."; return 16; }
                if ! git merge --no-edit "${base_branch}"; then
                    git mergetool && \
                    git commit -a
                    [[ "$?" -eq 0 ]] || { ERROR_OUTPUT="Merge is not completed"; return 17; }
                fi
                echo -e "Merged ${BOLD_LIGHT_CYAN}${base_branch}${NC} into ${BOLD_LIGHT_CYAN}${descendant}${NC}."
                merge_config_recursive "${descendant}"
                [[ "$?" -eq 0 ]] || return "$?"
            done

            return 0
        }
        ! (( CREATED_EDIT_BRANCH )) || return 0
        merge_config_recursive "${EDIT_BRANCH}"
    }

    push_config () {
        git push || { ERROR_OUTPUT="Pushing new commits failed"; return 18; }
    }

    apply_working_copy_changes () {
        local return_code

        git checkout "${CONFIG_UPDATE_BRANCH}" >/dev/null 2>&1 || \
            { ERROR_OUTPUT="Could not checkout ${BOLD_LIGHT_CYAN}${CONFIG_UPDATE_BRANCH}${NC}."; return 19; }
        pushd .. >/dev/null 2>&1 && \
        rm -rf "${CONFIGS_DIR}" && \
        cp -r "${CONFIGS_WORKING_DIR}" "${CONFIGS_DIR}" && \
        popd >/dev/null 2>&1
        [[ "$?" -eq 0 ]] || { ERROR_OUTPUT="Could not apply working copy changes (copy failed)."; return 20; }

        echo "Applied the working copy changes to the real config files."
        return 0
    }

    create_config_symlinks () {
        local locations location config_name config_filepath

        [[ -f "${CONFIGS_LOCATION_FILE}" ]] || return 0
        IFS=$'\n' read -d '' -r -a locations < "${CONFIGS_LOCATION_FILE}"
        for location in "${locations[@]}"; do
            config_name="$(echo "${location}" | cut -d: -f1)"
            config_filepath="$(echo "${location}" | cut -d: -f2)"
            pushd "${HOME}" >/dev/null 2>&1
            config_filepath="$(abspath "${config_filepath}")"
            popd >/dev/null 2>&1
            if [[ -L "${config_filepath}" ]]; then
                if [[ "$(readlink -- "${config_filepath}")" != "${CONFIGS_DIR}/${config_name}" ]]; then
                    rm -f "${config_filepath}" && \
                    ln -s "${CONFIGS_DIR}/${config_name}" "${config_filepath}"
                    [[ "$?" -eq 0 ]] || \
                        { ERROR_OUTPUT="Could not modify the existing symbolic link ${BOLD_LIGHT_BLUE}${config_filepath}${NC}."; \
                          return 21; }
                fi
            else
                if [[ -f "${config_filepath}" ]]; then
                    mv "${config_filepath}" "${config_filepath}.bak" || \
                        { ERROR_OUTPUT="Could not create a backup of the old config file ${BOLD_LIGHT_BLUE}${config_filepath}${NC}."; \
                          return 22; }
                fi
                ln -s "${CONFIGS_DIR}/${config_name}" "${config_filepath}" || \
                    { ERROR_OUTPUT="Could not create a symbolic link for the config file ${BOLD_LIGHT_BLUE}${config_filepath}${NC}."; \
                      return 23; }
            fi
        done

        echo "Successfully updated symlinks to all config files."
        return 0
    }

    cleanup () {
        popd >/dev/null 2>&1
        rm -rf "${CONFIGS_WORKING_DIR}" || { ERROR_OUTPUT="Could not cleanup the working directory"; return 24; }

        echo "Cleaned the working directory."
        return 0
    }

    init_variables "$@" && \
    if (( SHOW_HELP )); then
        show_help
        return "$?"
    elif (( SHOW_VERSION )); then
        show_version
        return "$?"
    fi
    create_working_copy_and_fetch_remote_configs
    return_code="$?"
    if ! (( FETCH_REMOTE_ONLY )) && [[ "${return_code}" -eq 0 ]]; then
        add_config && \
        edit_config && \
        merge_config && \
        push_config
        return_code="$?"
    fi
    if [[ "${return_code}" -eq 0 ]]; then
        apply_working_copy_changes && \
        create_config_symlinks
        return_code="$?"
    fi
    cleanup
    return_code="$?"
    if [[ -n "${ERROR_OUTPUT}" ]]; then
        echo -e "${BOLD_LIGHT_RED}ERROR:${NC} ${ERROR_OUTPUT}"
    fi
    return "${return_code}"
}

config-update "$@"

# vim: ft=sh:tw=120