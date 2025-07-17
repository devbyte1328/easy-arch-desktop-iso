### This repo is being overhauled due to some fundamental issues with the previous method. README.md will be updated once the overhaul process is complete.

"This project is MIT-licensed, except for files in /conf/brave/ which are MPL 2.0 due to their origin from the Brave Browser."

🍎🐧 macOS / Linux (Terminal)

Docker:  
sudo docker build -t easyarch .  
sudo docker run --rm -t --privileged -v "$PWD/out:/build/out" easyarch
{ sudo docker build -t easyarch . && sudo docker run --rm -t --privileged -v "$PWD/out:/build/out" easyarch; } 2>&1 | tee logs.txt

Native:  
sudo ./compile-iso.sh  

