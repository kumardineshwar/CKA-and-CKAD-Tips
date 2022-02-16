#!/bin/bash
 
#Author : kumardineshwar@gmail.com
#Usases : This script will take the Users Project backup
 
ADMINS="kumardineshwar@gmail.com"

# Login using system:admin or cluster-admin/reader equivalanet role
oc login -u system:admin >/dev/null


# Getting Project List excluding infra projects

oc get ns | egrep -v ^"openshift|kube|default|trident|NAME" | awk '{print $1}' |tee .project-list

# Include what need to take backup
OBJECT="configmaps endpoints persistentvolumeclaims secrets serviceaccounts services deploy deploymentconfigs rolebindings cronjobs buildconfigs imagestreams imagestreamtags imagetags networkpolicies rolebindings routes netpol pvc"
 
#Creating Backup Folder

DT=$(date +%A)
DT2=$(date +%d)

#Backup Directory

BKPDIR="/ocp-backup/backup/$DT"

[ ! -d $BKPDIR ] && mkdir -p $BKPDIR
 
for NS in $(cat .project-list)
do
	mkdir -p $BKPDIR/$NS
	oc get ns $NS -o json | jq 'del(.metadata.managedFields)' > $BKPDIR/$NS/$NS-ns.json
	
	for RS in $OBJECT
	do
		oc -n $NS get $RS -o json | jq 'del(.items[].metadata.managedFields,.items[].status)' >  $BKPDIR/$NS/$NS-$RS.json
	done
	echo " Project $NS Backup Done"
done

oc get pv | grep -v NAME | awk '{print $1,$6}' > .all-pv

[ ! -d $BKPDIR/PV ] && mkdir $BKPDIR/PV
while read VOL
do
	PV=$(echo $VOL | awk '{print $1}')
	NAME=$(echo $VOL | awk '{print $2}'|tr "/" "_")
	PV_NAME=$(oc get pv $PV -o jsonpath='{.spec.claimRef.namespace}_{.spec.claimRef.name}{"\n"}')
	oc get pv $PV -o json |jq 'del(.metadata.managedFields)' > $BKPDIR/PV/$PV_NAME.json
	echo "PV $NAME Spec Done"
done < .all-pv

tar cvzf OCP-Project-backup-$DT2.tgz $BKPDIR >/dev/null
date > /ocp-backup/backup/Project-Backup/.OCP-Project-backup-md5sum-$DT2
md5sum OCP-Project-backup-$DT2.tgz >> /ocp-backup/backup/Project-Backup/.OCP-Project-backup-md5sum-$DT2
rm -f /ocp-backup/backup/Project-Backup/OCP-Project-backup-$DT2.tgz
mv OCP-Project-backup-$DT2.tgz /ocp-backup/backup/Project-Backup/
 
 
cat <<EOF>/tmp/mail
Hello Team,
 
Please find the OCP Cluster Project Backup status
 
======================================================================================
Project List
===============
$(cat .project-list)
 
PVC List
===============
$(cat .all-pv)
 
Backup File Name
===============
$(ls -lhtr /ocp-backup/backup/Project-Backup/OCP-Project-backup-$DT2.tgz)
======================================================================================
 
Regards,
OCPAdmin

EOF
 
 
cat /tmp/mail | mailx -s "OCP Cluster Project Backup" -r OCP4Admin $ADMINS
rm -f .all-pv .project-list /tmp/mail