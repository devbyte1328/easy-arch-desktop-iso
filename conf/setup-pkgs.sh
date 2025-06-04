#!/bin/bash

sudo ufw enable
sudo ufw default reject incoming
sudo ufw default allow outgoing
sudo chmod +x /usr/bin/yay
