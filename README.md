# config-update - Manage your config files and their differences between multiple hosts

## Introduction

Many tools exist to manage configuration files between different machines. However, none of these tools is good at
managing differences between several hosts and it is not always possible to write configuration files with conditional
statements. `config-update` keeps configuration files in sync on multiple machines based on Git and uses branching to
manage an arbitrary count of different versions of these files. When you update a configuration file, the tool
automatically detects dependent versions and merges changes into all correspondent branches.


## Requirements

This tool needs Python 2.7 or 3.3+. You can check your installed Python version with

```bash
python --version
```

If you are running a recent Linux distribution or macOS, an appropriate Python version should already be installed.


## Installation

### For zsh users

If you are a zsh user, you can install `config-update` as a zsh plugin and get zsh autocompletion for config files and
Git branches.

#### Using zplug

1.  Add `zplug "IngoMeyer441/config_update"` to your `.zshrc`.

2.  Run

    ```bash
    zplug install
    ```

3.  Afterwards, you can use the new command `config-update` with ready-to-use autocompletion.

#### Manual

1.  Clone this repository and source `config_update.plugin.zsh` in your `.zshrc`

2.  Afterwards, you can use the new command `config-update` with ready-to-use autocompletion.


### For non-zsh users

You can use the included Makefile to install the `config-update` command. Run

```bash
sudo make install
```

to install `config-udpate` to `/usr/local/bin/`. You can override the `PREFIX` variable to install to another location,
for example

```bash
sudo make PREFIX=/opt/config_update install
```

to install to `/opt/config_update/bin/`.

## Usage

### Setup of a config repository

1.  Create a new central Git repository (for example on [GitHub](https://www.github.com/) or
    [GitLab](https://www.gitlab.com/)).

2.  Add all config files you want to manage as a *base template* to the `master` branch. *Base template* refers to a
    version of each config file that is a common denominator for each of your hosts. These versions do not need to be
    complete; lines that belong to a specific machine should be deleted. The names of the added files don't need to
    match their real config file names, so you could remove leading dots if you want to, for example. You can use
    subdirectories to structure your files.

    You only need to add all files manually once.

3.  Create a file `.config_locations` in the repository root and add it to the master branch as well. Create one line
    for each of your configuration files:

    ```
    <Git name>:<config host path>
    ```

    Each line maps a file of the Git repository to its configuration path on a host machine. Config pathes can be
    absolute or relative to your home directory. For example, use

    ```
    vimrc:.vimrc
    ```

    to manage your `.vimrc` as `vimrc` in your config repository.

4.  Create Git branches for each different config version you need. Add system specific lines to your configurations,
    commit the result and push it to your central repository. You can use multiple levels of nested branches if you want
    to. For example to you could create the following branching structure:

    ```
     ubuntu *   * fedora
             \ /
    macos *   * linux
           \ /
            * master
    ```

    In that case, `linux` is second level of templating branch to serve as a common denominator for `ubuntu` and
    `fedora`.


### Setup config-update on each host

1.  `config-update` itself is configured by environment variables. Define

    ```bash
    export CONFIG_UPDATE_CONFIGS_REPO_URL="<Repo URL>"
    export CONFIG_UPDATE_BRANCH="<Git branch for this host>"
    ```

    If `config-update` is installed as standalone program (via Makefile), you must additionally configure where to store
    the local copy of your config repository, for example:

    ```bash
    export CONFIG_UPDATE_CONFIG_ROOT_DIR="${HOME}/.config_update"
    ```

2.  Run `config-update` to install the configuration files from your central repository. If the configuration files
    already exist, a backup is created (moved to `<name>.bak`). For each configuration file a symbolic link is created
    that points to the corresponding file in your Git repository.

3.  Rerun `config-update` to get configuration file updates.


### Change configuration files

1.  Run

    ```bash
    config-update <Git config name> <Git branch>
    ```

    to update a configuration file on the given branch. If branch is omitted, `master` is used. The tool opens the
    config file with the editor configured by the `VISUAL` environment variable. After closing the editor, you can alter
    another config file or you will be prompted for a commit message and a new Git commit will be created. If you
    updated a branch that serves as a template branch (for example `master`), all subsequent branches will be
    automatically updated by merging your newly created commit. In the case of merge conflicts `git mergetool` is run to
    resolve each conflict. Afterwards, changes are pushed to your central repository.

    If the given config file does not exist, you are prompted for the file location on disk. In that case a new config
    file is added to the repository and to `.config_locations`.

    **Update example:**

    If you update the `master` branch in that scenario

    ```
     ubuntu *   * fedora
             \ /
    macos *   * linux
           \ /
            * master
    ```

    you would get

    ```
          ubuntu *       * fedora
                 |\     /|
                 | \   / |
                 |  \ /  |
                 |   *   | linux
       (ubuntu~) *  /|   * (fedora~)
       macos *   | | |   |
             |\  | | |   |
             | \  \/ |  /
             |  \ /\ | /
             |   *  \|/ master
    (macos~) *   |   * (linux~)
              \  |  /
               \ | /
                \|/
                 * (master~)
    ```



2.  Rerun

    ```bash
    config-update
    ```

    on each other host to synchronize the new config file versions.
