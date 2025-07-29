# Mise Tool Management Documentation

`mise` (formerly `rtx`) is a powerful tool version manager used in the Talos GitOps Home-Ops Cluster to ensure a consistent and reproducible development environment. This document details its purpose, installation, and usage for managing various development tools.

## Purpose

`mise` aims to:

- **Standardize Tool Versions**: Ensure all developers use the same versions of tools (e.g., `task`, `kubectl`, `flux`) as defined in the project's `.mise.toml` file.
- **Simplify Setup**: Streamline the process of setting up a new development environment.
- **Automate Installation**: Automatically install and manage tool versions without manual intervention.
- **Improve Collaboration**: Reduce "it works on my machine" issues by enforcing consistent toolchains.

## Installation

To install `mise` on your system, follow these steps:

1. **Download and Install `mise`**:

    ```bash
    curl https://mise.jdx.dev/install.sh | sh
    ```

    This script will install `mise` and add it to your shell's PATH.

2. **Configure Shell Integration**: Follow the on-screen instructions provided by the installer to integrate `mise` with your shell (e.g., `~/.zshrc`, `~/.bashrc`). This typically involves adding a line like `eval "$(mise activate)"`.

3. **Verify Installation**:

    ```bash
    mise --version
    ```

    You should see the installed `mise` version.

## Usage

Once `mise` is installed and configured, it will automatically manage tool versions based on the `.mise.toml` file in the project root.

### Installing Project Tools

To install all tools specified in the project's `.mise.toml` file:

```bash
mise install
```

This command will read the `.mise.toml` file, identify the required tools and their versions, and install them if they are not already present.

### Activating Tools

`mise` automatically activates the correct tool versions when you navigate into a directory containing a `.mise.toml` file. You don't typically need to run explicit activation commands.

### Adding New Tools

To add a new tool to the project (e.g., `node`):

1. **Add to `.mise.toml`**: Edit the `.mise.toml` file and add the tool and its desired version.

    ```toml
    [tools]
    node = "20.11.0"
    ```

2. **Install**: Run `mise install` to install the newly added tool.

### Updating Tools

To update a specific tool to a newer version:

1. **Update `.mise.toml`**: Change the version number in the `.mise.toml` file.
2. **Install**: Run `mise install` to update the tool.

### Listing Installed Tools

To see a list of all tools installed by `mise`:

```bash
mise ls
```

### Running Commands with Specific Tool Versions

You can temporarily run a command with a specific tool version without changing the project's `.mise.toml`:

```bash
mise exec python@3.10 -- python your_script.py
```

## Related Files

- [`.mise.toml`](../../.mise.toml) - The main configuration file for `mise`, defining project-specific tool versions.

Please ensure this file is created with the exact content provided. After creation, use the `attempt_completion` tool to report the successful creation of the file.
