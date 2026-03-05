FROM docker.io/library/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Minimal, non-root toolbox for Claude Code + git workflows.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      bash \
      zsh \
      git \
      less \
      jq \
      nano \
      ripgrep \
      fzf \
      openssh-client \
      vim-tiny \
      openjdk-17-jdk-headless \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Non-root user matching the host UID/GID (pass via build args) ----
ARG USERNAME=sandbox
ARG USER_UID=1000
ARG USER_GID=1000

RUN set -eux; \
    if getent group "${USER_GID}" >/dev/null; then \
        :; \
    else \
        groupadd --gid "${USER_GID}" "${USERNAME}"; \
    fi; \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/zsh "${USERNAME}"; \
    mkdir -p /workspace "/home/${USERNAME}/.claude"; \
    chown -R "${USERNAME}:${USER_GID}" /workspace "/home/${USERNAME}/.claude"

ENV DEBIAN_FRONTEND=""

ENV SHELL=/bin/zsh
ENV EDITOR=vim
ENV VISUAL=vim

WORKDIR /workspace

# ---- Entrypoint ----
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh
# Git fancyness
COPY git-completion.bash /usr/local/bin/git-completion.bash
RUN chmod 0755 /usr/local/bin/git-completion.bash

USER ${USERNAME}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zsh", "-l"]

# ---- Claude Code (native installer) ----
ARG CLAUDE_CODE_CHANNEL=latest
RUN curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_CODE_CHANNEL}

# Make sure the installed CLI is on PATH for login shells and non-login execs.
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
RUN echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> /home/${USERNAME}/.zshrc
RUN echo "alias clauded='claude --dangerously-skip-permissions'" >> /home/${USERNAME}/.zshrc
# Add autocompletion to git
RUN echo "zstyle ':completion:*:*:git:*' script /usr/local/bin/git-completion.bash" >> /home/${USERNAME}/.zshrc
RUN echo 'autoload -Uz compinit && compinit' >> /home/${USERNAME}/.zshrc
