# AI Sandbox Experiment

Experiment with setting up and running a sandbox environment to run AI agents.

### Setup:

1. Install Podman: https://podman.io
2. Once you have the Podman VM running, run `build-sandbox.sh`. If the image is successfully built, you only need to run this once.
3. Run `run-sandbox.sh` to start the container and get into the sandbox terminal.
4. Run `claude` or `clauded` (dangerously skips permissions) and follow the instructions.

### Updating the image:
The container is kept between runs and stays pinned to the image and mounts it was created from, so rebuilding the image or adding a bridge repo doesn't change an existing container.
After running `build-sandbox.sh` again, or when a bridge mount is missing, `run-sandbox.sh` detects it and offers to recreate the container (or run `run-sandbox.sh --recreate` to skip the prompt).
Anything stored only inside the container, such as the Claude Code login, is lost and must be set up again.
Once no container uses the old image, remove it with `podman image prune`.

### Sharing code with the Sandbox:
Each project has its own bare "bridge" repo in `${SANDBOX_FOLDER}` and a matching folder in the container's workspace:

| Project | Bridge on host | Mounted in container | Workspace folder |
|---------|----------------|----------------------|------------------|
| Kit     | `kit-bridge.git` | `/kit-bridge.git` | `/workspace/kit` |
| TTS     | `tts-bridge.git` | `/tts-bridge.git` | `/workspace/tts` |

In each workspace folder the bridge is already set up as the `origin` remote.

1. From your host working repository add the git remote for the matching sandbox bridge:
   - run in Terminal: `git remote add sandbox ${SANDBOX_FOLDER}/kit-bridge.git` # or tts-bridge.git
2. Push the branch you want the agent to run on:
   - run in Terminal, e.g. `git push sandbox develop` # change develop to your desired branch name
3. From the VM / Container terminal, in the workspace folder of your choice, fetch and checkout the working branch: 
   - `git fetch --all --prune`
   - `git checkout -b feature/ai-work develop` # change branch names to your desired ones

### Retrieving the changes from Sandbox:
Once the agent finished work and committed the changes:
1. From the VM / Container, push changes to the git bridge: `git push origin feature/ai-work`
2. From the host working repository, fetch the changes: `git fetch sandbox --prune`
3. Diff the changes with your working tree to selectively apply them or cherry-pick the whole commit. 
