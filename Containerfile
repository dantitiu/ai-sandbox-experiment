FROM docker.io/library/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ---- System packages ----
# openjdk-17 is required by Android Gradle Plugin; unzip/wget are needed by sdkmanager.
# NDK host tools (clang wrappers, codegen binaries) are prebuilt for x86_64.
# On the ARM Podman VM we need QEMU user-mode emulation + the x86_64 dynamic
# linker so the kernel can transparently execute those foreign binaries via
# binfmt_misc. Without these two packages the NDK C/C++ build fails with:
#   qemu-x86_64-static: Could not open '/lib64/ld-linux-x86-64.so.2'
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      wget \
      unzip \
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
      procps \
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

# ---- Android SDK ----
# Bump ANDROID_API_LEVEL here when you move to a new platform version.
ARG ANDROID_HOME=/opt/android-sdk
ARG ANDROID_API_LEVEL=35
ARG ANDROID_BUILD_TOOLS_VERSION=35.0.0
ARG ANDROID_NDK_VERSION=28.0.13004108
ARG CMAKE_VERSION=3.22.1

ENV ANDROID_HOME=${ANDROID_HOME}
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# Download cmdline-tools as root, install SDK packages as root into /opt.
# The directory is made world-readable so the non-root user can invoke sdkmanager/gradle.
# Scrape the canonical Linux download URL directly from the Android Studio downloads page.
# This avoids hardcoding a build number that Google rotates with every release.
# Google ships the zip with a top-level folder called "cmdline-tools"; rename to "latest"
# so sdkmanager's self-update mechanism works correctly.
RUN set -eux; \
    mkdir -p "${ANDROID_HOME}/cmdline-tools"; \
    TOOLS_URL="$(curl -fsSL https://developer.android.com/studio \
        | grep -o 'https://dl.google.com/android/repository/commandlinetools-linux-[0-9]*_latest\.zip' \
        | head -1)"; \
    echo "Downloading cmdline-tools from: ${TOOLS_URL}"; \
    wget -q "${TOOLS_URL}" -O /tmp/cmdline-tools.zip; \
    unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools"; \
    mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"; \
    rm /tmp/cmdline-tools.zip; \
    chmod -R a+rX "${ANDROID_HOME}"

# Accept licenses and install the required SDK components.
# --no_https is omitted intentionally; the image build environment has outbound HTTPS.
# Give the sandbox user full ownership of the SDK so that sdkmanager can still
# be invoked at runtime (e.g. to install extra packages) without sudo.
RUN yes | sdkmanager --licenses >/dev/null 2>&1 || true && \
    sdkmanager \
      "platform-tools" \
      "platforms;android-${ANDROID_API_LEVEL}" \
      "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
      "ndk;${ANDROID_NDK_VERSION}" \
      "cmake;${CMAKE_VERSION}" && \
    chown -R "${USERNAME}:${USER_GID}" "${ANDROID_HOME}"

# NDK home is a versioned subdirectory; expose it explicitly for CMake / AGP.
ENV ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}"

# Pre-warm the Gradle wrapper download cache directory so first build is faster.
RUN mkdir -p /opt/gradle-cache && chmod -R a+rwX /opt/gradle-cache

# Point Gradle at the shared cache volume (see run-sandbox.sh for the mount).
# This avoids re-downloading dependencies every time the container is rebuilt.
ENV GRADLE_USER_HOME=/opt/gradle-cache
# Robolectric's native runtime has no linux-aarch64 binary (Podman on Apple Silicon
# runs an ARM VM). Force the pure-JVM runtime, which is functionally identical.
ENV GRADLE_OPTS="-Drobolectric.usePreinstrumentedJars=false"

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
RUN echo 'export ANDROID_HOME=/opt/android-sdk'    >> /home/${USERNAME}/.zshrc
RUN echo 'export ANDROID_SDK_ROOT=/opt/android-sdk' >> /home/${USERNAME}/.zshrc
RUN echo 'export ANDROID_NDK_HOME=/opt/android-sdk/ndk/28.0.13004108' >> /home/${USERNAME}/.zshrc
RUN echo 'export GRADLE_USER_HOME=/opt/gradle-cache' >> /home/${USERNAME}/.zshrc
RUN echo 'export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"' >> /home/${USERNAME}/.zshrc
RUN echo "alias clauded='claude --dangerously-skip-permissions'" >> /home/${USERNAME}/.zshrc
RUN echo "alias gitfet='git fetch --all --prune'" >> /home/${USERNAME}/.zshrc
# Add autocompletion to git
RUN echo "zstyle ':completion:*:*:git:*' script /usr/local/bin/git-completion.bash" >> /home/${USERNAME}/.zshrc
RUN echo 'autoload -Uz compinit && compinit' >> /home/${USERNAME}/.zshrc
