#!/bin/bash

path_to_drive="/dev/zvol/rpool/data/"
aws_s3_bucket="bucket-for-task1"
import_status=""
count=0

if ! [ -x "$(command -v aws)" ]; then
  echo 'AWS CLI is not installed. Please install AWS CLI!' >&2
  exit 1
fi

if ! aws s3 ls > /dev/null ; then
    echo "aws cli isn't configured"
    exit 1
fi

#vm_id=101
for vm_id in $(qm list | awk '{ print $1 }' | grep -iv VMID) ; do
	snap_file=${vm_id}.vpc
	echo "Migrate vm - "$vm_id   ## need to remove
	qemu-img convert -f raw -O vpc ${path_to_drive}vm-${vm_id}-disk-0 $snap_file

	echo "Send image to S3"
	aws s3 cp $snap_file s3://$aws_s3_bucket/

	#### Import image
	snap_import_task_id=$(aws ec2 import-snapshot \
		--description "alpine-$vm_id" \
		--disk-container Format=VHD,UserBucket="{S3Bucket=${aws_s3_bucket},S3Key=$snap_file}" \
		--output json | jq -r .ImportTaskId)

	echo "Running import-snapshot"
	until [ "$import_status" == "completed" ]; do
		full_status=$(aws ec2 describe-import-snapshot-tasks \
			--import-task-ids $snap_import_task_id --output json)

		import_status=$(echo $full_status | jq -r '.ImportSnapshotTasks[] .SnapshotTaskDetail.Status')
		import_percentage=$(echo $full_status | jq -r '.ImportSnapshotTasks[] .SnapshotTaskDetail.Progress')

		if [[ "$import_percentage" != "null" ]]; then
			echo -ne "\rStatus: "$import_percentage"%"
		else
			echo -ne "\rStatus: 100%"
			snap_id=$(echo $full_status | jq -r '.ImportSnapshotTasks[] .SnapshotTaskDetail.SnapshotId')
		fi

		if [[ $count -gt 50 ]]; then
			echo -e "\nSomething went wrong!"
			echo "Last output was: \n" $full_status
			exit 1;
		fi

		((count++)); sleep 10
	done
	echo -e "\nMigrate vm $vm_id - Done!"

	#### Get snapshot size
	volume_size=$(aws ec2 describe-snapshots \
		--snapshot-ids $snap_id \
		--output json | jq -r '.Snapshots[] .VolumeSize')

	echo "Registering AMI"
	image_id=$(aws ec2 register-image --virtualization-type hvm --root-device-name /dev/sda1 \
		--architecture x86_64 --name alpine-$vm_id \
		--block-device-mappings '[{"DeviceName": "/dev/sda1", "Ebs": {"SnapshotId": "'$snap_id'", "VolumeType": "gp2","VolumeSize": '$volume_size'}}, {"VirtualName": "ephemeral21", "DeviceName": "/dev/sdb"}]' --output json | jq -r .ImageId)
	./migrate_fire_rules.sh $vm_id
	echo "Creating instance"
	aws ec2 run-instances \
	--image-id $image_id \
	--count 1 \
	--instance-type t2.micro \
	--key-name aws_key \
	--security-groups SecGroup$vm_id --output json
done
