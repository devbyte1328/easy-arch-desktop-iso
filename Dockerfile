FROM archlinux:latest

RUN pacman -Sy --noconfirm archiso git base-devel go sudo python python-pip

RUN useradd -m main

RUN echo "main ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/main

RUN chmod 0440 /etc/sudoers.d/main

COPY . /build

WORKDIR /build

# Set env var so scripts that use $SUDO_USER behave normally
ENV SUDO_USER=main

CMD ./compile.sh
