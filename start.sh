#!/bin/bash

sudo apt install git -y
git clone https://github.com/vatanas/task
cd /task
terraform init
terraform apply -auto-approve