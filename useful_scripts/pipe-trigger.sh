#!/bin/bash

#aws codepipeline get-pipeline --name WB.gateway.dev >gw-pipeline.json --profile new-account-04 --region us-east-1
aws codepipeline update-pipeline --cli-input-json file://gw-pipeline.json --profile new-account-04 --region us-east-1 
aws codepipeline start-pipeline-execution --name WB.gateway.dev --profile new-account-04 --region us-east-1
