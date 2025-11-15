
# Introduction

This is a quick and dirty way to get all of the secure infra you need to use LLMs on AWS' free
tier plan. You will find terraform containing all the configuration for your AWS instance, a few shell scripts that the terraform will consume to bootstrap your instance, and some configuration 
files for the self healing of the API services that will run on your instances.

## Infrastructure List

- 2x EC2 w/ EBS storage [bastion host & API server]
- API Gateway
- security groups for EC2s

## Terraform Info
