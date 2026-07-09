#!/bin/bash

docker build -f .config/utility/dev/Dockerfile -t t6server-tests .

docker run --rm t6server-tests
