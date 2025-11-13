#!/bin/bash

kubectl get pods -n testing -o jsonpath='{.items[*].metadata.name}'
