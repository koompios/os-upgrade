#! /bin/bash

PASSWORD="";

function checkpw() {
  IFS= read -p "Enter your password: " PASSWD
  sudo -k
  if sudo -lS <<< $PASSWD &> /dev/null;
  then
      PASSWORD=$PASSWD
      clear;
  else 
      faillock --user $USER --reset
      echo 'Invalid password. Try again!'
      checkpw
  fi
}

checkpw