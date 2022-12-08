#!/bin/bash

function get_S3_KMS() {
        #How to determine what CloudFormation stack an AWS resource belongs to using AWS CLI?:
        #https://stackoverflow.com/questions/58724180/how-to-determine-what-cloudformation-stack-an-aws-resource-belongs-to-using-aws

        get_S3_owner_stack="aws cloudformation describe-stack-resources \
        --physical-resource-id "codepipeline-artifact-store-04" \
        --profile 04 --region us-east-1 2>/dev/null | grep -i "StackName" | head -n 1 | cut -d ":" -f 2 | cut -d "," -f 1"
        Current_StackName=$(eval $get_S3_owner_stack)
        echo -e "\nGot Pre-req Stack name > $Current_StackName \n"


        get_s3_command="aws cloudformation describe-stacks --stack-name $Current_StackName --profile 04 \
        --region us-east-1 --query \"Stacks[0].Outputs[?OutputKey=='ArtifactBucket'].OutputValue\" --output text"
        S3Bucket=$(eval $get_s3_command)
        echo -e "\nGot S3 bucket name > $S3Bucket \n"

        get_cmk_command="aws cloudformation describe-stacks --stack-name $Current_StackName --profile 04 \
        --region us-east-1 --query \"Stacks[0].Outputs[?OutputKey=='CMK'].OutputValue\" --output text"
        CMKArn=$(eval $get_cmk_command)
        echo -e "Got CMK ARN > $CMKArn \n"
}


                        get_S3_KMS

			echo -e "\nExecuting in DEPLOY Account, Deploying Pipeline on Deployment Account..."
                        exec_pipedeploy="aws cloudformation deploy --stack-name "WB-Live-Analytics"   --template-file DeployAcct/code-pipeline.yaml --parameter-overrides file://$(pwd)/params.json  --capabilities CAPABILITY_NAMED_IAM --profile 04 --region us-east-1" 
                        eval $exec_pipedeploy
                        wait

			echo -e "\nExecuting in Deploy Account, Updating KMS in Pre-req stack with Build IAM role..."
                        exec_preReq_update="aws cloudformation deploy --stack-name $Current_StackName   --template-file DeployAcct/pre-reqs.yaml --parameter-overrides ProjectName=$Build_ProjectName CodeBuildCondition=true  --capabilities CAPABILITY_NAMED_IAM --profile 04 --region us-east-1"
			eval $exec_preReq_update

			wait
                        echo -e "\nExecuting in DEPLOY Account, Updating Pipeline Source stage with DevAcct IAM role..."
                        exec_pipeUpdate="aws cloudformation deploy --stack-name "WB-Live-Analytics"   --template-file DeployAcct/code-pipeline.yaml --parameter-overrides CrossAccountCondition=true  --capabilities CAPABILITY_NAMED_IAM --profile 04 --region us-east-1"
                        eval $exec_pipeUpdate
