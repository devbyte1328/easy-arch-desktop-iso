"This project is MIT-licensed, except for files in /conf/brave/ which are MPL 2.0 due to their origin from the Brave Browser."




🪟 Windows (Command Prompt / PowerShell)

1. Build the Docker image:

docker build -t archiso-builder .

2. Run the Docker container:

docker run --rm -it --privileged --entrypoint /bin/bash -v "%cd%":/home/builder/iso -w /home/builder/iso archiso-builder -c "./compile-iso.sh"

###################################

🍎🐧 macOS / Linux (Terminal)

1. Build the Docker image:

docker build -t archiso-builder .

2. Run the Docker container:

docker run --rm -it --privileged --entrypoint /bin/bash -v "$(pwd)":/home/builder/iso -w /home/builder/iso archiso-builder -c "./compile-iso.sh"


