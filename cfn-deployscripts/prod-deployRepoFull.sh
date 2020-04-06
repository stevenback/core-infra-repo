#!/bin/bash

PROFILE=$1

if [ -z $PROFILE ]; then
	echo ""
	echo "#######################################################"
	echo ""
	echo "You must enter an AWS Profile. ie ( prod-deploy.sh <profile> )"
	echo "If you do not have one configured, run: aws configure"
	echo ""
	echo "#######################################################"
	echo ""
	exit 1;
fi

echo "##############################################################################"
echo "This will deploy the Repo Fed environment to the $PROFILE environment."
echo "This environment builds under the assumption the that following parameters"
echo "have been populated in AWS Parameter Store"
echo " - RepoAdminToken"
echo " - RepoGithubUser"
echo " - RepoGithubToken"
echo "##############################################################################"
echo "Continue? (y/n)"
read ANSWER

if [ $ANSWER == 'y' ]; then
	aws cloudformation deploy --template-file ../cfn-templates/Repofederate.yaml --stack-name wawa-Repofederate-dev-9-3-1 \
	--parameter-overrides \
	BranchName="master" \
	ConsoleInstanceType="t3.medium" \
	EngineInstanceType="t3.medium" \
	Environment="dev931" \
	PrivateSubnets=subnet-0254c99a5be4b0ce6,subnet-021b936d29d5df90d \
	PublicSubnets=subnet-020b5791b86cfa890,subnet-0dcd41e4b2e3dc8a3 \
	DatabaseSubnets=subnet-0a9d053a6e44d76ea,subnet-007e58616033561f6 \
	VPCId="vpc-005aacebb974f5f42" \
	WawaRedhatAMI="ami-0e129082a83709a91" \
	RepoRepoUrl="github.com/wawa/core-infra-Repoconfig.git" \
	VPCCidr="10.161.96.0/23" \
	DBInstanceType="db.t3.medium" \
	DBUsername="admin" \
	DBAllocatedStorage="100" \
	RepoCertArn="arn:aws:acm:us-east-1:836182291071:certificate/7503d07f-4774-40a9-ac58-58cf38ace705" \
	ConsoleStaticIp="10.161.96.140" \
	PublicHostedDomainUrl="wicd9292.com" \
	ImpervaSecurityGroup="sg-0a2dc01222eaea5ab" \
	RepoSNSARN="arn:aws:sns:us-east-1:836182291071:wawa-awsadmins" \
	EngineASGMinSize=2 \
	LicenseFile="Repofederate.1503989.WF.development.lic" \
	--capabilities CAPABILITY_NAMED_IAM --profile $PROFILE; 
else
	echo "Exiting..."
	exit 0
fi

