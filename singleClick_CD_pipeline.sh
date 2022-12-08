#!/bin/bash


echo "Phase I > Checking and Installing Pre-requesets..."
sleep 2

#Function to get S3Name & KMSKey existing on Deployment Account.
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


function pipe_deployment() {

  while true
  do
	echo -e "\nPhase II > Pipeline Deployment on Target AWS Deployment account...\n"

        #Know more about Changing variable value to Uppercase or Lowercase: https://www.shellscript.sh/tips/case/
        echo -n "please Enter Environment Name [Ex.: Live] >  "
        read Environment_Name 
       	Environment_Name=${Environment_Name,,} 
       	Environment_Name=${Environment_Name^}
	echo $Environment_Name
        echo -n "please Enter Build Project Name [Ex.: Bot] >  "
        read Build_ProjectName 
       	Build_ProjectName=${Build_ProjectName,,}
       	Build_ProjectName=${Build_ProjectName^}
	echo $Build_ProjectName
        echo -n "please Enter Project Reposiroty Name in CodeCommit >  "
        read RepositoryCodeCommit_Name
        echo -n "[Optional] pass in the custom name for buildspec.yaml file if exist [ex.: buildspec-inbox.yaml] >  "
        read CustomBuildSpec
        echo -n "please Enter Branch Name [EX.: master] >  "
        read Branch_Name
        echo -n "please Enter Beanstalk Application Name >  "
        read BeansTalkApp_Name
        echo -n "please Enter Beanstalk Environment Name > "
        read BeansTalkEnv_Name
        echo -n "please Enter Devlopment account-ID [current One: 074697765782] > "
        read DevAccountID
        #Checking Vars empty values.
        if [[ -z $Environment_Name || -z $Build_ProjectName || -z $Branch_Name || -z $DevAccountID || -z $RepositoryCodeCommit_Name || -z $DevAccountID || -z $BeansTalkApp_Name || -z $BeansTalkEnv_Name ]];
        then
                echo -e "\nInvalid or Empty Entries, Please Try again!!\n"
        else
                #check if any stack exist and contain resource with the passed physical id.
                #Note: 2>/dev/null -it passes any error away so that if stack does not exist, command exec will 
                #return empty string not "Normal" output error value.

                get_pipeline_owner_stack="aws cloudformation describe-stack-resources \
                --physical-resource-id "WB-$Environment_Name-$Build_ProjectName" \
                --profile 04 --region us-east-1 2>/dev/null \
                | grep -i "StackName" | head -n 1 | cut -d ":" -f 2 | cut -d "," -f 1 2>/dev/null"
                PipeStack_exist=$(eval $get_pipeline_owner_stack)

                if [[ -z $PipeStack_exist ]];
                then
                        #get s3 bucket and CMKArn values 
                        get_S3_KMS
                        echo -e "\nExecuting in DEPLOY Account, Deploying Pipeline on Deployment Account..."
                        exec_pipedeploy="aws cloudformation deploy --stack-name "WB-$Environment_Name-$Build_ProjectName" \
				--template-file $(pwd)/DeployAcct/code-pipeline.yaml \
                                --parameter-overrides DevAccount=$DevAccountID Environment=$Environment_Name \
                                RepositoryCodeCommit=$RepositoryCodeCommit_Name ProjectName=$Build_ProjectName \
                                CMKARN=$CMKArn S3Bucket=$S3Bucket \
                                Branch=$Branch_Name \
                                BeansTalkAppName=$BeansTalkApp_Name \
                                BeansTalkEnvName=$BeansTalkEnv_Name \
                                --capabilities CAPABILITY_NAMED_IAM --profile 04 --region us-east-1"
                        eval $exec_pipedeploy
                        wait
                        echo -e "\nExecuting in DEPLOY Account, Updating KMS in Pre-req stack with Build IAM role..."
                        exec_preReq_update="aws cloudformation deploy --stack-name $Current_StackName \
			--template-file $(pwd)/DeployAcct/pre-reqs.yaml \
                        --parameter-overrides ProjectName=$Build_ProjectName Environment=$Environment_Name CodeBuildCondition=true \
                        --profile 04 --region us-east-1"

                        eval $exec_preReq_update
                        wait
                        echo -e "\nExecuting in DEPLOY Account, Updating Pipeline Source stage with DevAcct IAM role..."
                        exec_pipeUpdate="aws cloudformation deploy --stack-name "WB-$Environment_Name-$Build_ProjectName" \
				--template-file $(pwd)/DeployAcct/code-pipeline.yaml \
                                --parameter-overrides CrossAccountCondition=true \
                                --capabilities CAPABILITY_NAMED_IAM --profile 04 --region us-east-1"
                        eval $exec_pipeUpdate
                        wait
			echo -e "\nStack WB-$Environment_Name-$Build_ProjectName has been created Successfully...\n"
                        echo -e "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"

				
                else
                        echo -e "\nStack with name: $PipeStack_exist already exist with the required resources as well.."
				
		
                fi
        fi

  done

}

echo -e "\nChecking if the Requested Pre-requesites already installed or not...\n"
S3_bucket="aws s3 ls codepipeline-artifact-store-04 --profile 04 --region us-east-1"
s3_exist=$(eval $S3_bucket)

#learn more about KMS and Aliases: https://github.com/awsdocs/aws-kms-developer-guide/blob/master/doc_source/alias-manage.md
KMS_key="aws kms list-aliases --region us-east-1 --profile 04 | grep -x "alias/codepipeline-crossaccounts""
key_exist=$(eval $KMS_key)

Dev_IAM_Role="aws iam list-roles --region us-east-1 --profile default | grep -x "DeploymentAcctCodePipelineCodeCommitRole""
role_exist=$(eval $Dev_IAM_Role)

#learn more about grouping in if condition: https://stackoverflow.com/questions/14964805/groups-of-compound-conditions-in-bash-test

if [[ -z "$s3_exist" &&  -z "$key_exist" && -z $role_exist ]];
then
	while true
	do
        	echo -e "\nResources ARE not there, Deploying pre-requisite stack to the Deployment account... \n"

        	echo -n "please Enter preferred CloudFormation StackName For Deployment account pre-req resources >  "
        	read Deploy_PreReq_StackName
        	echo -n "please Enter preferred CloudFormation StackName For Dev account pre-req resources >  "
        	read Dev_PreReq_StackName
       		echo -n "please Enter Dev. account-ID [current One: 074697765782] > "
        	read DevAccountID
        	echo -n "please Enter Deploy. account-ID [current One: 042264081003] > "
        	read DeployAccountID


        	#Checking Vars empty values.
        	if [[ -z $Deploy_PreReq_StackName || -z $Dev_PreReq_StackName || -z $DevAccountID || -z $DeployAccountID ]];
        	then
                	echo -e "\nInvalid or Empty Entries, Please Try again!!\n"
        	else	
                	#checking if there are stacks with the same name...
                	#NOte: grep with -x option, returns true only if it finds the [exact] match for the passed text,
			#not match a slice part
                	list_DeployStacks="aws cloudformation list-stacks --profile 04 --region us-east-1 \
				| grep -x "$Deploy_PreReq_StackName""
                	DeployStack_exist=$(eval $list_DeployStacks)
                	list_DevStacks="aws cloudformation list-stacks --profile default --region us-east-1 \
				| grep -x "$Dev_PreReq_StackName""
                	DevStack_exist=$(eval $list_DevStacks)

                	if [[ -z $DeployStack_exist && -z $DevStack_exist ]];
                	then
                        	echo -e "\nExecuting in DEPLOY Account, Deploying S3-Artifact-Store & KMS Encryption key..."
                        	exec_deploy="aws cloudformation deploy --stack-name $Deploy_PreReq_StackName \
                        	--template-file $(pwd)/DeployAcct/pre-reqs.yaml \
                        	--parameter-overrides DevAccount=$DevAccountID --profile 04 --region us-east-1"
				eval $exec_deploy
                        	wait

                        	echo -e "\nExecuting in DEV Account, Deploying dev account assumable role..."

                        	#execute function to get S3 and KMS existing on Deployment Account.
				get_S3_KMS

				exec_dev="aws cloudformation deploy --stack-name $Dev_PreReq_StackName \
				--template-file $(pwd)/DevAccount/deployacct-codepipeline-codecommit.yaml \
				--capabilities CAPABILITY_NAMED_IAM \
				--parameter-overrides CMKARN=$CMKArn DevAccount=$DevAccounTID DeploymentAccount=$DeployAccountID \
				--profile default --region us-east-1"
				eval $exec_dev
				
				#Pipeline deployment function execution
				pipe_deployment

			else
				echo -e "\nStack Names $Deploy_PreReq_StackName & $Dev_PreReq_StackName already in-use"			       				break

			fi

	              fi

		done

	else
		sleep 1
		echo "The Required Resources already there, Proceeding to the Next Deployment steps..."
		#execute function to get S3 and KMS existing on Deployment Account.
		#get_S3_KMS
                #Pipeline deployment function execution
                pipe_deployment
	fi



	
