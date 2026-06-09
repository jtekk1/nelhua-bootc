#!/bin/bash

sudo $(which bluebuild) generate-iso \
  --tempdir /var/tmp \
  --iso-name nelhua-linux-kde.iso \
  image ghcr.io/jtekk1/nelhua-kde:latest
