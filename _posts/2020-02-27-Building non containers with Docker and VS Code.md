---
title: Building non-containers with Docker and VS Code
date: 2020-02-27 14:48:00 +0100
categories: [Build Automation]
tags: [VS Code, Docker]
redirects:
  - /building-non-containers-with-docker-and-vs-code
  - /building-non-containers-with-docker-and-vs-code-ck74szgf807g9d9s1s6o88c8f
---

> In this post:
>
> - example configuration
> - command line breakdowns
> - links to relevant documentation

- - -

I recently set up containerised builds for [my website](https://schichler.dev/) [It's not quite ready yet.] and thought I'd share the configuration for others to use as reference.

💁‍♂️ *Note that I'm using Docker mainly to avoid installing tooling globally. If this isn't the case for you, then a different build strategy will likely be better.*

Additionally, some command lines will contain placeholders with example content `{EX:like this}` and optional segments `[OPT:like this]`. You will have to at least remove the respective parentheses and `EX:` or `OPT:` to make them work.

### .vscode/tasks.json

```jsonc
{
    // See https://go.microsoft.com/fwlink/?LinkId=733558
    // for the documentation about the tasks.json format¹
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Create {EX:target/bundle/schichler-dev}/",
            "type": "shell",
            "command": "mkdir --parents {EX:target/bundle/schichler-dev}",
            "windows": {
                "command": "if not exist {EX:target/bundle/schichler-dev}/NUL mkdir {EX:target\\bundle\\schichler-dev}"
            }
        },
        {
            "label": "Build {EX:schichler-dev}",
            "dependsOn": [
                "Create {EX:target/bundle/schichler-dev}/"
            ],
            "type": "shell",
            "command": "docker build -t {EX:schichler-dev} -f {EX:schichler-dev/Dockerfile} {EX:.} && docker run [OPT:--read-only] --mount type=bind,source=${workspaceFolder}{EX:/target/bundle/schichler-dev},destination=/mnt/target --rm {EX:schichler-dev}",
            // The task group shown by Tasks: Run Build Task.
            "group": "build",
            "presentation": {
                // Automatically show the problems panel if any problems are matched.
                // The default here is "never".
                "revealProblems": "onProblem"
            },
            // Prevents Code's prompt whether to show output.
            // This was added automatically when I selected never to.
            // You can add problem matchers² to make Code recognise
            "problemMatcher": []
        }
    ]
}
```
{: file=".vscode/tasks.json"}

¹ [Integrate with External Tools via Tasks](https://go.microsoft.com/fwlink/?LinkId=733558); comment from default *tasks.json*.  
² See [# Processing task output with problem matchers](https://code.visualstudio.com/docs/editor/tasks#_processing-task-output-with-problem-matchers).

This creates the following entry in the Tasks: Run Build Task command menu, by default bound to Ctrl + Shift + B:  
![[Select the build task to run] > Build schichler-dev](/assets/img/posts/2020-02-27-Building non containers with Docker and VS Code/run task Build schichler-dev.png)  
...which runs the following shell commands in dependent sequence:
```sh
docker build -t {EX:schichler-dev} -f {EX:schichler-dev/Dockerfile} {EX:.}
docker run [OPT:--read-only] --mount type=bind,source=${workspaceFolder}{EX:/target},destination=/mnt/target --rm {EX:schichler-dev}
```

*In my case*:

<!-- markdownlint-disable ol-prefix -->

1. [Make the directory (`mkdir`)](http://www.man7.org/linux/man-pages/man1/mkdir.1.html) path (`--parents`) `target/bundle/schichler-dev`, if it doesn't exist yet (`--parents`).  
  💁‍♂️ *Windows requires special handling here, since Windows's [MKDIR](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/md) will error if the directory already exists, isn't configurable in that regard, and also doesn't support `/` as path separator.  
  `CMD /E:ON /C` makes sure command extensions are on (default since 2000/XP) so we can create the entire path at once.  
  `if not exist target/bundle/schichler-dev/NUL` makes sure `target/bundle/schichler-dev` doesn't exist **as a directory** already, by checking for the special file `NUL` within it.  
  See <https://stackoverflow.com/a/4165472>.*
2.
   1. [Build](http://manpages.org/docker-build) a Docker image and tag (`-t`) it as `schichler-dev`(`:latest`).  
Use the Docker file (`-f`) located at `schichler-dev/Dockerfile`³ and use `.`⁴ as context root.
   2. [Run](http://manpages.org/docker-run) the Docker image tagged `schichler-dev` with its internal file system read-only (`--read-only`)⁵, while mounting (`--mount`) `${workspaceFolder}/target/bundle/schichler-dev`⁶ mutably inside the container as `/mnt/target`. Remove (`--rm`) the container instance afterwards.

³ You don't need to specify this for a `Dockerfile` in the context root.  
⁴ The folder opened in Code is the working directory for the command.  
⁵ This isn't strictly necessary, but Docker may be able to start the container a little faster if it has a matching optimisation.  
⁶ Full paths are required here.  
💁‍♂️ *Code handily expands `${workspaceFolder}` to what we need. Show the suggestions (default: `Ctrl + Space`) within the `"command"` parameter's value (but only before the first such expansion, it seems) for a list of other values that can be interpolated.*

### Dockerfile

End your (Unix) Dockerfile with:
```Dockerfile
CMD rm -fr /mnt/target/* \
    && cp -vr --no-target-directory {EX:bundle} /mnt/target
```

This *in my case*:

1. [Removes (`rm`)](http://www.man7.org/linux/man-pages/man1/rm.1.html), recursively (`-r`), all files and directories (`*`) inside the mounted host directory.

2. [Copies (`cp`)](http://www.man7.org/linux/man-pages/man1/cp.1.html), recursively (`-r`), the contents of (`--no-target-directory`) my build directory inside the container (`bundle`) into the mounted host directory visible at `/mnt/target` inside the container.  
💁‍♂️ *Instead of writing `--no-target-directory`, you could append* `/*` *to the source directory to use shell expansion. I don't know whether this makes a practical difference.*

### Running the Task

You can now run the build task by pressing `Ctrl + Shift + B` and then `Enter`.

Code should show the output of the command in a new task terminal window.
