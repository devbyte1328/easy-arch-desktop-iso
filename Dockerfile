FROM archlinux:latest

ENV TERM xterm

RUN pacman -Sy --noconfirm archiso git base-devel sudo go

RUN useradd -m -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

USER builder
WORKDIR /home/builder

ENTRYPOINT ["bash"]

