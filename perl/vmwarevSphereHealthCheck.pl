#!/usr/bin/perl -w
# Author: William Lam
# Website: www.virtuallyghetto.com

use 5.10.0;
use strict;
use warnings;
use Math::BigInt;
use Tie::File;
use POSIX qw/mktime/;
use Socket;
use Getopt::Long;
use POSIX qw(ceil floor);
use VMware::VIRuntime;
use VMware::VILib;
use Net::SMTP;

########### DO NOT MODIFY PAST HERE ###########

################################
# VERSION
################################
my $version = "6.5.0";
$Util::script_version = $version;

my @supportedVersion = qw(4.0.0 4.1.0 5.0.0 5.1.0 5.5.0 6.0.0 6.5.0);

my %opts = (
	cluster => {
		type => "=s",
		help => "The name of a vCenter cluster to query",
		required => 0,
	},
	datacenter => {
		type => "=s",
		help => "The name of a vCenter datacenter to query",
		required => 0,
	},
	hostlist => {
		type => "=s",
		help => "File containting list of ESX/ESXi host(s) to query",
		required => 0,
	},
	vmlist => {
		type => "=s",
		help => "File containting list of VM(s) to query",
		required => 0,
	},
	type => {
		type => "=s",
		help => "Type: [vcenter|datacenter|cluster|host]\n",
		required => 1,
	},
	report => {
		type => "=s",
		help => "The name of the report to output. Please add \".html\" extension",
		required => 0,
		default => "vmware_health_report.html",
	},
	logcount => {
		type => "=s",
		help => "The number of lines to output from hostd logs",
		required => 0,
		default => 15,
	},
	vmperformance => {
		type => "=s",
		help => "Enable VM Performance gathering [yes|no] (Can potentially double your runtime)",
		required => 0,
		default => "no",
	},
	hostperformance => {
		type => "=s",
		help => "Enable Host Performance gathering [yes|no] (Can potentially increase your runtime)",
		required => 0,
		default => "no",
	},
	clusterperformance => {
		type => "=s",
		help => "Enable Cluster Performance gathering [yes|no] (Can potentially increase your runtime)",
		required => 0,
		default => "no",
	},
	email => {
		type => "=s",
		help => "[yes|no]",
		required => 0,
		default => "no",
	},
	demo => {
		type => "=s",
		help => "[yes|no]",
		required => 0,
		default => "no",
	},
	conf => {
		type => "=s",
		help => "File containing Host and VM specific configurations to output",
		required => 0,
	},
	printerfriendly => {
		type => "=s",
		help => "Whether the html output will be printer friendly [yes|no]",
		required => 0,
		default => "no",
	},
	debug  => {
		type => "=s",
		help => "Enable/Disable debugging to help William troubleshoot [0|1]",
		required => 0,
	},
);

# validate options, and connect to the server
Opts::add_options(%opts);

# validate options, and connect to the server
Opts::parse();
Opts::validate();
Util::connect();

###############
# GLOBAL VARS
###############

my ($system_name, $host_name,$hostlist,$vmlist,$service_content,$hostType,$apiType,$apiVersion,$report,$my_time,$start_time,$demo,$email,$printerfriendly,$logcount,$vmperformance,$hostperformance,$clusterperformance,$type,$clusterInput,$datacenterInput,$hostfileInput,$cluster_view,$cluster_views,$datacenter_views,$datacenter_view,$host_view,$conf,$debug);
my (@vmw_apps,@perf_host_list,@vms_perf,@hosts_in_cluster,@portgroups_in_cluster,@hosts_seen,@datastores_seen,@hosts_in_portgroups,@dvs,@vmsnapshots,@vmdeltas) = ();
my (%hostlists,%vmlists,%configurations,%vmmac_to_portgroup_mapping,%vswitch_portgroup_mappping,%lun_row_info,%luns,%datastore_row_info,%datastores,%portgroup_row_info,%seen_dvs) = ();
my ($hardwareConfigurationString,$stateString,$hostString,$healthHardwareString,$healthSoftwareString,$nicString,$configString,$hbaString,$cdpString,$lunString,$datastoreString,$cacheString,$portgroupString,$multipathString,$dvsString,$logString,$taskString,$numaString,$hostPerfString,$vmString,$vmstateString,$vmconfigString,$vmstatString,$vmftString,$vmeztString,$vmtoolString,$vmstorageString,$vmnetworkString,$vmthinString,$vmPerfString,$vmsnapString,$vmcdString,$vmflpString,$vmrdmString,$vmdeltaString,$vmnpivString,$advString,$agentString,$mgmtString,$vmrscString,$capString,$vmdeviceString,$iscsiString) = ("","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","");
my (@datastore_cluster_jump_tags,@cluster_jump_tags,@host_jump_tags,@vm_jump_tags) = ();


###############
# PROPERTY filters
###############
my $datacenter_properties = [ 'name' ];

###############
# COLORS
###############
my $green = "#00FF00";
my $red = "#FF0000";
my $orange = "#FF6600";
my $yellow = "#FFFF33";
my $white = "#FFFFFF";
my $light_green = "#66FF99";
my $light_red = "#FF6666";

############################
# PARSE COMMANDLINE OPTIONS
#############################

$system_name = Opts::get_option('server');
$report = Opts::get_option('report');
$demo = Opts::get_option('demo');
$email = Opts::get_option('email');
$logcount = Opts::get_option('logcount');
$vmperformance = Opts::get_option('vmperformance');
$hostperformance = Opts::get_option('hostperformance');
$clusterperformance = Opts::get_option('clusterperformance');
$type = Opts::get_option('type');
$clusterInput = Opts::get_option('cluster');
$datacenterInput = Opts::get_option('datacenter');
$conf = Opts::get_option('conf');
$hostlist = Opts::get_option('hostlist');
$vmlist = Opts::get_option('vmlist');
$printerfriendly = Opts::get_option('printerfriendly');
$debug = Opts::get_option('debug');

##########################
# DEFAULT CONFIGUFRATION
##########################
my $EMAIL_HOST = 'emailserver';
my $EMAIL_DOMAIN = 'localhost.localdomain';
my @EMAIL_TO = 'william@primp-industries.com.com,tuan@primp-industries.com';
my $EMAIL_FROM = 'vMA@primp-industries.com';
my $YELLOW_WARN = 30;
my $ORANGE_WARN = 15;
my $RED_WARN = 10;
my $SNAPSHOT_YELLOW_WARN = 15;
my $SNAPSHOT_ORANGE_WARN = 30;
my $SNAPSHOT_RED_WARN = 60;
my $SYSTEM_LICENSE="yes";
my $SYSTEM_FEATURE="yes";
my $SYSTEM_PERMISSION="yes";
my $SYSTEM_SESSION="yes";
my $SYSTEM_HOST_PROFILE="yes";
my $SYSTEM_PLUGIN="yes";
my $DVS_SUMMARY="yes";
my $DVS_CAPABILITY="yes";
my $DVS_CONFIG="yes";
my $DATASTORE_CLUSTER_SUMMARY="yes";
my $DATASTORE_CLUSTER_POD_CONFIG="yes";
my $DATASTORE_CLUSTER_POD_ADV_CONFIG="yes";
my $DATASTORE_CLUSTER_POD_STORAGE="yes";
my $CLUSTER_SUMMARY="yes";
my $CLUSTER_PERFORMANCE="no";
my $CLUSTER_HA="yes";
my $CLUSTER_DRS="yes";
my $CLUSTER_DPM="yes";
my $CLUSTER_AFFINITY="yes";
my $CLUSTER_GROUP="yes";
my $CLUSTER_RP="yes";
my $CLUSTER_VAPP="yes";
my $HOST_HARDWARE_CONFIGURATION="yes";
my $HOST_MGMT="yes";
my $HOST_STATE="yes";
my $HOST_HEALTH="yes";
my $HOST_PERFORMANCE="no";
my $HOST_NIC="yes";
my $HOST_HBA="yes";
my $HOST_CAPABILITY="yes";
my $HOST_CONFIGURATION="yes";
my $HOST_VMOTION="yes";
my $HOST_GATEWAY="yes";
my $HOST_ISCSI="yes";
my $HOST_IPV6="yes";
my $HOST_FT="yes";
my $HOST_SSL="yes";
my $HOST_DNS="yes";
my $HOST_UPTIME="yes";
my $HOST_DIAGONISTIC="yes";
my $HOST_AUTH_SERVICE="yes";
my $HOST_SERVICE="yes";
my $HOST_NTP="yes";
my $HOST_VSWIF="yes";
my $HOST_VMKERNEL="yes";
my $HOST_VSWITCH="yes";
my $HOST_SNMP="yes";
my $HOST_FIREWALL="yes";
my $HOST_POWER="yes";
my $HOST_FEATURE_VERSION="yes";
my $HOST_ADVOPT="yes";
my $HOST_AGENT="yes";
my $HOST_NUMA="yes";
my $HOST_CDP="yes";
my $HOST_DVS="yes";
my $HOST_LUN="yes";
my $HOST_DATASTORE="yes";
my $HOST_CACHE="yes";
my $HOST_MULTIPATH="yes";
my $HOST_PORTGROUP="yes";
my $HOST_LOG="yes";
my $HOST_TASK="yes";
my $VM_STATE = "yes";
my $VM_CONFIG="yes";
my $VM_STATS="yes";
my $VM_RESOURCE_ALLOCATION="yes";
my $VM_PERFORMANCE="no";
my $VM_FT="yes";
my $VM_EZT="yes";
my $VM_THIN="yes";
my $VM_DEVICE="yes";
my $VM_STORAGE="yes";
my $VM_NETWORK="yes";
my $VM_SNAPSHOT="yes";
my $VM_DELTA="yes";
my $VM_CDROM="yes";
my $VM_FLOPPY="yes";
my $VM_RDM="yes";
my $VM_NPIV="yes";
my $VM_TOOL="yes";
my $VMW_APP="yes";
my $VPX_SETTING="yes";

############################
# START OF SCRIPT
############################

($service_content,$hostType,$apiType,$apiVersion) = &getServiceInfo();

&validateSystem($apiVersion);
&processOptions($type,$apiType,$conf);
&processAdditionalConf();
&startReport();
&startBody($apiType,$apiVersion);
&getSystemSummary($service_content,$hostType,$apiType,$apiVersion);
&getCluster($type,$apiType,$apiVersion);
&getDatastoreCluster($type,$apiType,$apiVersion,$service_content);
&getHost($type,$apiType,$apiVersion,$service_content);
&getVM($type,$apiType,$apiVersion,$service_content);
&getVPXSettings($VPX_SETTING,$apiType,$service_content);
&getVMwareApps($VMW_APP,$apiType,$service_content);
&endBody();
&endReport();
&emailReport();

############################
# END OF SCRIPT
############################

Util::disconnect();

#####################
# HELPER FUNCTIONS
#####################

sub emailReport {
	if($email eq "yes") {
		my $smtp = Net::SMTP->new($EMAIL_HOST ,Hello => $EMAIL_DOMAIN,Timeout => 30,);

		unless($smtp) {
			die "Error: Unable to setup connection with email server: \"" . $EMAIL_HOST . "\"!\n";
		}

		open(DATA, $report) || die("Could not open the file");
		my @report = <DATA>;
		close(DATA);

		my @EMAIL_RECIPIENTS = $smtp->recipient(@EMAIL_TO,{SkipBad => 1});

		my $boundary = 'frontier';

		$smtp->mail($EMAIL_FROM);
		$smtp->to(@EMAIL_TO);
		$smtp->data();
		$smtp->datasend('From: '.$EMAIL_FROM."\n");
		$smtp->datasend('To: '.@EMAIL_TO."\n");
		$smtp->datasend('Subject: VMware vSphere Health Check Report Completed - '.giveMeDate('MDYHMS'). " (" . $system_name . ")\n");
		$smtp->datasend("MIME-Version: 1.0\n");
		$smtp->datasend("Content-type: multipart/mixed;\n\tboundary=\"$boundary\"\n");
		$smtp->datasend("\n");
		$smtp->datasend("--$boundary\n");
		$smtp->datasend("Content-type: text/plain\n");
		$smtp->datasend("Content-Disposition: quoted-printable\n");
		$smtp->datasend("\nReport $report is attached!\n");
		$smtp->datasend("--$boundary\n");
		$smtp->datasend("Content-Type: application/text; name=\"$report\"\n");
		$smtp->datasend("Content-Disposition: attachment; filename=\"$report\"\n");
		$smtp->datasend("\n");
		$smtp->datasend("@report\n");
		$smtp->datasend("--$boundary--\n");
		$smtp->dataend();
		$smtp->quit;
	}
}

sub getServiceInfo {
	my $sc = Vim::get_service_content();
	# service content
	# esx,embeddedEsx,gsx,vpx
	# HostAgent,VirtualCenter
	# 4.0.0
	return ($sc,$sc->about->productLineId,$sc->about->apiType,$sc->about->version);
}

sub getSystemSummary {
	my ($sc,$htype,$atype,$aversion) = @_;

	my $summary_start = "<div id=\"tab1\" class=\"content\">\n";

	###########################
	# SYSTEM BUILD INFO
	###########################

	if($atype eq 'VirtualCenter') {
		$summary_start .= "<h2>VMware vCenter System Summary</h2>"
	} else {
		if($htype eq 'esx') {
			$summary_start .= "<h2>VMware ESX System Summary</h2>"
		}elsif($htype eq 'embeddedEsx') {
			$summary_start .= "<h2>VMware ESXi System Summary</h2>"
		}
	}

	$summary_start .= "\n<table border=\"1\">\n";
	$summary_start .= "<tr><th>FULL NAME</th><th>VCENTER SERVER</th><th>INSTANCE UUID</th></tr>\n";
	$summary_start .= "<tr><td>".$sc->about->fullName."</td><td>$system_name</td><td>".$sc->about->instanceUuid."</td></tr>\n";
	$summary_start .= "</table>\n";

	###########################
	# LICENSE
	###########################
	my ($features,$feature_string,$feature_info_string) = ("","","");

	if($SYSTEM_LICENSE eq "yes") {
		my $licenseMgr = Vim::get_view (mo_ref => $sc->licenseManager);

		$summary_start .= "<h3>Licenses:</h3>\n";
		$summary_start .= "<table border=\"1\">\n";
		$summary_start .= "<tr><th>NAME</th><th>EDITION</th><th>LICENSE</th><th>COST UNIT</th><th>TOTAL</th><th>CONSUMED</th><th>AVAILABLE</th></tr>\n";

		my $licenses = $licenseMgr->licenses;
		foreach(@$licenses) {
			if($demo eq "no") {
					my $licenseName = $_->name;
					my $licenseEdition = $_->editionKey;
					my $licenseKey = $_->licenseKey;
					my $licenseCost = $_->costUnit;
					my $licenseUsed = int(($_->used ? $_->used : 0));
					my $licenseTotal = $_->total;
					my $licenseConsumed = ($licenseTotal - $licenseUsed);
					$summary_start .= "<tr><td>".$licenseName."</td><td>".$licenseEdition."</td><td>".$licenseKey."</td><td>".$licenseCost."</td><td>".$licenseTotal."</td><td>".$licenseUsed."</td><td>".$licenseConsumed."</td></tr>\n";
					my $licenseProperties = $_->properties;
					if($licenseProperties) {
						$feature_info_string .= "<tr><th>EDITION w/FEATURES</th><th>EXPIRATION (HOURS)</th><th>EXPIRATION (MINS)</th><th>EXPIRATION DATE</th></tr>\n";
						$feature_info_string .= "<tr><td><b>".$licenseEdition."</b></td>\n";
					}
					foreach(@$licenseProperties) {
						if($_->key ne 'feature') {
				if($_->key eq 'expirationHours' ) { $feature_info_string .= "<td>".$_->value."</td>"; }
				if($_->key eq 'expirationMinutes' ) { $feature_info_string .= "<td>".$_->value."</td>"; }
				if($_->key eq 'expirationDate' ) { $feature_info_string .= "<td>".$_->value."</td></tr>\n"; }
						} else {
							my $feature = $_->value;
							$features .= "<tr><td>".$feature->value."</td></tr>\n";
						}
					}
			} else {
	$summary_start .= "<tr><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td></tr>\n";
	}
			$feature_string .= $feature_info_string . $features;
			($features,$feature_info_string) = ("","");
		}
		$summary_start .= "</table>\n";
	}

	###########################
	# FEATURES
	###########################
	if($SYSTEM_FEATURE eq "yes" && $SYSTEM_LICENSE eq "yes") {
		$summary_start .= "<h3>Features:</h3>\n";
		$summary_start .= "<table border=\"1\">\n";

		if($demo eq "no") {
			$summary_start .= $feature_string;
		} else {
			$summary_start .= "<tr><td>DEMO_MODE</td></tr>\n";
		}
		$summary_start .= "</table>\n";
	}

	###########################
	# PERMISSIONS
	###########################
	if($SYSTEM_PERMISSION eq "yes") {
		$summary_start .= "<h3>Permissions:</h3>\n";
		$summary_start .= "<table border=\"1\">\n";
		$summary_start .= "<tr><th>USER/GROUP</th><th>ROLE</th><th>DEFINED IN</th><th>PROPAGATE</th><th>IS GROUP</th></tr>\n";

		my $authMgr = Vim::get_view (mo_ref => $sc->authorizationManager);
		my $roleLists = $authMgr->roleList;
		my %rolemapping;
		foreach(@$roleLists) {
			$rolemapping{$_->roleId} = $_->name;
		}

		if($demo eq "no") {
			eval {
				my $permissions = $authMgr->RetrieveAllPermissions();
				foreach(@$permissions) {
					my $ent = Vim::get_view(mo_ref => $_->entity, properties => ['name']);
					$summary_start .= "<tr><td>" . $_->principal . "</td><td>" . $rolemapping{$_->roleId} . "</td><td>" . $ent->{'name'} . "</td><td>" . (($_->propagate) ? "YES" : "NO") . "</td><td>" . (($_->group) ? "YES" : "NO") . "</td></tr>\n";
				}
			};
			if($@) { print "ERROR: Unable to query for permissions: " . $@ . "\n"; }
		} else {
			$summary_start .= "<tr><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td></tr>\n";
		}
		$summary_start .= "</table>\n";
	}

	###########################
	# SESSIONS
	###########################
	if($SYSTEM_SESSION eq "yes") {
		$summary_start .= "<h3>Active Session(s):</h3>\n";
		$summary_start .= "<table border=\"1\">\n";
		$summary_start .= "<tr><th>USERNAME</th><th>FULL NAME</th><th>LOGON TIME</th><th>LAST ACTIVE</th></tr>\n";

		if($demo eq "no") {
			my $sessionMgr =  Vim::get_view (mo_ref => $sc->sessionManager);
			my $sess_list = $sessionMgr->sessionList;
			foreach(sort {$a->userName cmp $b->userName} @$sess_list) {
				$summary_start .=  "<tr><td>".$_->userName."</td><td>".$_->fullName."</td><td>".$_->loginTime."</td><td>".$_->lastActiveTime."</td></tr>\n";
			}
		} else {
			$summary_start .= "<tr><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td><td>DEMO_MODE</td></tr>\n";
		}
		$summary_start .= "</table>\n";
	}

	###########################
	# HOST PROFILES
	###########################
	if($SYSTEM_HOST_PROFILE eq "yes") {
		my $hostProfileMgr;
		eval {
			$hostProfileMgr = Vim::get_view (mo_ref => $sc->hostProfileManager);
		};
		if(!$@) {
			my $profiles = Vim::get_views (mo_ref_array => $hostProfileMgr->profile);
			my $hasProfile = 0;
			my $profile_string = "";
			foreach(sort {$a->name cmp $b->name} @$profiles) {
				$hasProfile = 1;
				my $profileDescription = "N/A";
				if($_->config->annotation) { $profileDescription = $_->config->annotation; }
				$profile_string .= "<tr><td>".$_->name."</td><td>".$profileDescription."</td><td>".$_->createdTime."</td><td>".$_->modifiedTime."</td><td>".(($_->config->enabled) ? "YES" : "NO")."</td><td>".$_->complianceStatus."</td></tr>\n";
			}
			if($hasProfile eq 1) {
				$summary_start .= "<h3>Host Profile(s):</h3>\n";
				$summary_start .= "<table border=\"1\">\n";
				$summary_start .= "<tr><th>PROFILE NAME</th><th>DESCRIPTION</th><th>CREATION TIME</th><th>LAST MODIFIED</th><th>ENABLED</th><th>COMPLIANCE STATUS</th></tr>\n";
				$summary_start .= $profile_string;
			}
		}
		$summary_start .= "</table>\n";
	}
	###########################
	# PLUGIN
	###########################
	if($SYSTEM_PLUGIN eq "yes") {
		my $extMgr;
		eval {
			$extMgr = Vim::get_view (mo_ref => $sc->extensionManager);
		};
		if(!$@) {
			my $extList = $extMgr->extensionList;
			my $ext_string = "";

			foreach(sort {$a->description->label cmp $b->description->label} @$extList) {
				$ext_string .= "<tr>";
				$ext_string .= "<td>".$_->description->label."</td>";
				$ext_string .= "<td>".($_->version ? $_->version : "N/A")."</td>";
				$ext_string .= "<td>".($_->company ? $_->company : "N/A")."</td>";
				$ext_string .= "</tr>\n";
			}
			$summary_start .= "<h3>Plugin(s):</h3>\n";
			$summary_start .= "<table border=\"1\">\n";
			$summary_start .= "<tr><th>PLUGIN NAME</th><th>VERSION</th><th>COMPANY</th></tr>\n";
			$summary_start .= $ext_string;
			$summary_start .= "</table>\n";
		}
	}

	$summary_start .= "\n</div>";
	print REPORT_OUTPUT $summary_start;
}

sub getCluster {
	my ($type,$atype,$aversion) = @_;

	my $cluster_count = 0;

	if($type eq 'cluster') {
		print REPORT_OUTPUT "<div id=\"tab2\" class=\"content\">";
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert cluster jump -->/\n";
		$cluster_count++;
		&printClusterSummary($cluster_view,$cluster_count,$atype,$aversion);
		print REPORT_OUTPUT "</div>\n";
	}elsif($type eq 'datacenter') {
		$cluster_views = Vim::find_entity_views(view_type => 'ClusterComputeResource',begin_entity => $datacenter_view);
		if($cluster_views) {
			print REPORT_OUTPUT "<div id=\"tab2\" class=\"content\">";
			#please do not touch this, else the jump tags will break
			print REPORT_OUTPUT "\n/<!-- insert cluster jump -->/\n";
			foreach(sort {$a->name cmp $b->name} @$cluster_views) {
				$cluster_count++;
				if($_->isa("ClusterComputeResource")) {
				       &printClusterSummary($_,$cluster_count,$atype,$aversion);
				}
			}
			print REPORT_OUTPUT "</div>\n";
		}
	}elsif($type eq 'vcenter') {
		if($cluster_views) {
			print REPORT_OUTPUT "<div id=\"tab2\" class=\"content\">";
			#please do not touch this, else the jump tags will break
			print REPORT_OUTPUT "\n/<!-- insert cluster jump -->/\n";
			foreach(sort {$a->name cmp $b->name} @$cluster_views) {
				$cluster_count++;
				if($_->isa("ClusterComputeResource")) {
				       &printClusterSummary($_,$cluster_count,$atype,$aversion);
				}
			}
		}
		print REPORT_OUTPUT "</div>\n";
	}
}

sub getDatastoreCluster {
	my ($type,$atype,$aversion) = @_;

	my $datastore_cluster_count = 0;

	if($type eq 'cluster' && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		print REPORT_OUTPUT "<div id=\"tab7\" class=\"content\">";
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert datastore cluster jump -->/\n";
		my $cluster_folder = Vim::get_view(mo_ref => $cluster_view->parent);
		my $cluster_parent = Vim::get_view(mo_ref => $cluster_folder->parent);
		$datastore_cluster_count++;
		&printDatacenterSummary($cluster_parent,$datastore_cluster_count,$atype,$aversion);
		print REPORT_OUTPUT "</div>\n";
	} elsif($type eq 'datacenter' && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		print REPORT_OUTPUT "<div id=\"tab7\" class=\"content\">";
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert datastore cluster jump -->/\n";
		$datastore_cluster_count++;
		&printDatacenterSummary($datacenter_view,$datastore_cluster_count,$atype,$aversion);
		print REPORT_OUTPUT "</div>\n";
	} elsif($type eq 'vcenter' && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		print REPORT_OUTPUT "<div id=\"tab7\" class=\"content\">";
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert datastore cluster jump -->/\n";
		$datacenter_views = Vim::find_entity_views(view_type => 'Datacenter'
                                                   , properties => $datacenter_properties );
		foreach(sort {$a->name cmp $b->name} @$datacenter_views) {
			$datastore_cluster_count++;
			&printDatacenterSummary($_,$datastore_cluster_count,$atype,$aversion);
		}
		print REPORT_OUTPUT "</div>\n";
	}
}

sub getHost {
	my ($type,$atype,$aversion,$sc) = @_;

	print REPORT_OUTPUT "<div id=\"tab3\" class=\"content\">\n";

	my $cluster_count = 0;

	if($type eq 'host') {
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert host jump -->/\n";
		&printHostSummary($host_view,undef,$cluster_count,$type,$atype,$aversion,$sc);
	}elsif($type eq 'datacenter') {
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert host jump -->/\n";
		foreach my $cluster(sort {$a->name cmp $b->name} @$cluster_views) {
			$cluster_count++;
			my $clusterTag = "host-".$cluster->name."-$cluster_count";
			my $clusterShortTag = $cluster->name;
			push @host_jump_tags,"&nbsp;&nbsp;&nbsp;<a href=\"#$clusterTag\">Cluster: $clusterShortTag</a><br/>\n";
			print REPORT_OUTPUT "<br/><a name=\"$clusterTag\"></a>\n";
			print REPORT_OUTPUT "<h2>Cluster: $clusterShortTag</h2>\n";
			my $hosts = Vim::get_views (mo_ref_array => $cluster->host);
			&printHostSummary($hosts,$cluster->name,$cluster_count,$type,$atype,$aversion,$sc);
		}
	}elsif($type eq 'cluster') {
		$cluster_count++;
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert host jump -->/\n";
		my $clusterTag = "host-".$cluster_view->name."-$cluster_count";
		my $clusterShortTag = $cluster_view->name;
		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;<a href=\"#$clusterTag\">Cluster: $clusterShortTag</a><br/>\n";
		print REPORT_OUTPUT "<br/><a name=\"$clusterTag\"></a>\n";
		print REPORT_OUTPUT "<h2>Cluster: $clusterShortTag</h2>\n";
		my $hosts = Vim::get_views (mo_ref_array => $cluster_view->host);
		&printHostSummary($hosts,$cluster_view->name,$cluster_count,$type,$atype,$aversion,$sc);
	}elsif($type eq 'vcenter') {
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert host jump -->/\n";
		foreach my $cluster(sort {$a->name cmp $b->name} @$cluster_views) {
			$cluster_count++;
			my $clusterTag = "host-".$cluster->name."-$cluster_count";
			my $clusterShortTag = $cluster->name;
			push @host_jump_tags,"&nbsp;&nbsp;&nbsp;<a href=\"#$clusterTag\">Cluster: $clusterShortTag</a><br/>\n";
			print REPORT_OUTPUT "<br/><a name=\"$clusterTag\"></a>\n";
			print REPORT_OUTPUT "<h2>Cluster: $clusterShortTag</h2>\n";

			my $hosts = Vim::get_views (mo_ref_array => $cluster->host);
			&printHostSummary($hosts,$cluster->name,$cluster_count,$type,$atype,$aversion,$sc);
		}
	}
	print REPORT_OUTPUT "</div>\n";
}

sub getVM {
	my ($type,$atype,$aversion,$sc) = @_;

	print REPORT_OUTPUT "<div id=\"tab4\" class=\"content\">\n";

	my $cluster_count = 0;

	if($type eq 'host') {
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert vm jump -->/\n";
		&printVMSummary($host_view,undef,$cluster_count,$type,$atype,$aversion,$sc);
	}elsif($type eq 'datacenter') {
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert vm jump -->/\n";
		foreach my $cluster(sort {$a->name cmp $b->name} @$cluster_views) {
			$cluster_count++;
			my $clusterTag = "vm-".$cluster->name."-$cluster_count";
			my $clusterShortTag = $cluster->name;
			push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;<a href=\"#$clusterTag\">Cluster: $clusterShortTag</a><br/>\n";
			print REPORT_OUTPUT "<br/><a name=\"$clusterTag\"></a>\n";
			print REPORT_OUTPUT "<h2>Cluster: $clusterShortTag</h2>\n";
			my $hosts = Vim::get_views (mo_ref_array => $cluster->host);
			&printVMSummary($hosts,$cluster->name,$cluster_count,$type,$atype,$aversion,$sc);
		}
	}elsif($type eq 'cluster') {
		$cluster_count++;
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert vm jump -->/\n";
		my $clusterTag = "vm-".$cluster_view->name."-$cluster_count";
		my $clusterShortTag = $cluster_view->name;
		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;<a href=\"#$clusterTag\">Cluster: $clusterShortTag</a><br/>\n";
		print REPORT_OUTPUT "<br/><a name=\"$clusterTag\"></a>\n";
		print REPORT_OUTPUT "<h2>Cluster: $clusterShortTag</h2>\n";
		my $hosts = Vim::get_views (mo_ref_array => $cluster_view->host);
		&printVMSummary($hosts,$cluster_view->name,$cluster_count,$type,$atype,$aversion,$sc);
	}elsif($type eq 'vcenter') {
		#please do not touch this, else the jump tags will break
		print REPORT_OUTPUT "\n/<!-- insert vm jump -->/\n";
		foreach my $cluster(sort {$a->name cmp $b->name} @$cluster_views) {
			$cluster_count++;
			my $clusterTag = "vm-".$cluster->name."-$cluster_count";
			my $clusterShortTag = $cluster->name;
			push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;<a href=\"#$clusterTag\">Cluster: $clusterShortTag</a><br/>\n";
			print REPORT_OUTPUT "<br/><a name=\"$clusterTag\"></a>\n";
			print REPORT_OUTPUT "<h2>Cluster: $clusterShortTag</h2>\n";
			my $hosts = Vim::get_views (mo_ref_array => $cluster->host);
			&printVMSummary($hosts,$cluster->name,$cluster_count,$type,$atype,$aversion,$sc);
		}
	}
	print REPORT_OUTPUT "</div>\n";
}

sub getVPXSettings {
	my ($vpxcheck,$atype,$sc) = @_;

	if($vpxcheck eq "yes" && $atype eq "VirtualCenter") {
		my $setting = Vim::get_view(mo_ref => $sc->setting);
		my $vpxSettings = $setting->setting;

		my $vpxString = "";
		if($vpxSettings) {
			print REPORT_OUTPUT "<div id=\"tab5\" class=\"content\">\n";
			print REPORT_OUTPUT "<h2>vCenter VPX Configurations</h2>\n";
			print REPORT_OUTPUT "<table border=\"1\">\n";
			print REPORT_OUTPUT "<tr><th>KEY</th><th>VALUE</th></tr>\n";
			foreach(sort {$a->key cmp $b->key} @$vpxSettings) {
				my $key = $_->key;
				my $value = $_->value;
				if($demo eq "yes" && ($key eq "VirtualCenter.InstanceName" || $key eq "VirtualCenter.DBPassword" || $key eq "VirtualCenter.LDAPAdminPrincipal" || $key eq "VirtualCenter.ManagedIP" || $key eq "VirtualCenter.VimApiUrl" || $key eq "VirtualCenter.VimWebServicesUrl" || $key eq "vpxd.motd" || $key =~ m/config.registry/ || $key =~ m/mail/ || $key =~ m/snmp/)) {
					$value = "DEMO_MODE";
				}
				$vpxString .= "<tr><td>".$key."</td><td>".$value."</tr>\n";
			}
			print REPORT_OUTPUT $vpxString;
			print REPORT_OUTPUT "</table>\n";
			print REPORT_OUTPUT "</div>\n";
		}
	}
}

sub getVMwareApps {
	my ($vmwcheck,$atype,$sc) = @_;

	if($vmwcheck eq "yes" && $atype eq "VirtualCenter") {

		my $vmwAppString = "";
		if(@vmw_apps) {
			print REPORT_OUTPUT "<div id=\"tab6\" class=\"content\">\n";
			print REPORT_OUTPUT "<h2>VMware and 3rd Party Applications in a VM</h2>\n";
			print REPORT_OUTPUT "<table border=\"1\">\n";
			print REPORT_OUTPUT "<tr><th>CLUSTER</th><th>VM NAME</th><th>VMWARE/3RD PARTY APPLICATION</th></tr>\n";
			foreach(@vmw_apps) {
				$vmwAppString .= $_;
			}
			print REPORT_OUTPUT $vmwAppString;
			print REPORT_OUTPUT "</table>\n";
			print REPORT_OUTPUT "</div>\n";
		}
	}
}

sub printVMSummary {
	my ($local_hosts,$cluster_name,$cluster_count,$type,$atype,$aversion,$sc) = @_;

	if(@$local_hosts) {
		foreach my $local_host(sort {$a->summary->config->name cmp $b->summary->config->name} @$local_hosts) {
			if($demo eq "no") {
				$host_name = $local_host->name;
			}

			#skip if host is not accessible
			next if($local_host->runtime->connectionState->val ne "connected");

			#skip if VM is not in valid list
			if($hostlist) {
				next if(!$hostlists{$local_host->name});
			}

			my $vms = Vim::get_views(mo_ref_array => $local_host->vm);
			foreach my $vm (sort {$a->name cmp $b->name} @$vms) {
				#skip if vm is disconnected
				next if(!defined($vm->config));

				#skip if VM is not in valid list
				if($vmlist) {
					my $vmname = $vm->name;
					next if(!$vmlists{$vmname});
				}

				######################
				# VM TAG
				######################
				if(defined($vm->tag)) {
					my $vmTags = $vm->tag;
					foreach(sort {$a->key cmp $b->key} @$vmTags) {
						my $tagString = "<tr><td>".$cluster_name."</td><td>".$vm->name."</td><td>".$_->key."</td></tr>\n";
						push @vmw_apps, $tagString;
					}
				}
				######################
				# VM STATE
				######################
				if($VM_STATE eq "yes") {
					$vmstateString .= "<tr>";

					## ESX/ESXi host ##
					$vmstateString .= "<td>".$host_name."</td>";

					## DISPLAY NAME ##
					$vmstateString .= "<td>".$vm->name."</td>";

					## BOOT TIME ##
					$vmstateString .= "<td>".($vm->runtime->bootTime ? $vm->runtime->bootTime : "N/A")."</td>";

					if($aversion eq '4.1.0' || ($aversion eq '5.0.0' || $aversion eq '5.1.0')) {
						## UPTIME ##
						$vmstateString .= "<td>".($vm->summary->quickStats->uptimeSeconds ? &getUptime($vm->summary->quickStats->uptimeSeconds) : "N/A")."</td>";
					}

					## ANNOTATION ##
					$vmstateString .= "<td>" . ($vm->config->annotation ? $vm->config->annotation : "N/A") . "</td>";

					## OVERALL STATUS ##
					my $vm_health = $vm->summary->overallStatus->val;
					if ($vm_health eq 'green') { $vmstateString .= "<td bgcolor=\"$green\">VM is OK</td>"; }
					elsif ($vm_health eq 'red') { $vmstateString .= "<td bgcolor=\"$red\">VM has a problem</td>"; }
					elsif ($vm_health eq 'yellow') { $vmstateString .= "<td bgcolor=\"$yellow\">VM<might have a problem</td>"; }
					else { $vmstateString .="<td bgcolor=\"gray\">UNKNOWN</td>"; }

					if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
						## HA PROTECTION ##
						if($vm->runtime->dasVmProtection) {
						$vmstateString .= "<td>".($vm->runtime->dasVmProtection->dasProtected ? "YES" : "NO")."</td>";
						} else { $vmstateString .= "<td>N/A</td>"; }
					} else { $vmstateString .= "<td>N/A</td>"; }

					if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
						## APP HEARTBEAT ##
						$vmstateString .= "<td>".($vm->guest->appHeartbeatStatus ? $vm->guest->appHeartbeatStatus : "N/A")."</td>";
					}

					## CONNECTION STATE ##
					$vmstateString .= "<td>".$vm->runtime->connectionState->val."</td>";

					## POWER STATE ##
					$vmstateString .= "<td>".$vm->runtime->powerState->val."</td>";

					## CONSOLIDATION ##
					if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
						$vmstateString .= "<td>".($vm->runtime->consolidationNeeded ? "YES" : "NO")."</td>";
					} else { $vmstateString .= "<td>N/A</td>"; }

					$vmstateString .= "</tr>";
				}
				######################
				# VM CONFIG
				######################
				if($VM_CONFIG eq "yes") {
					$vmconfigString .= "<tr>";

					## ESX/ESXi host ##
					$vmconfigString .= "<td>".$host_name."</td>";

					## DISPLAY NAME ##
					$vmconfigString .= "<td>".$vm->name."</td>";

					## VIRTUAL HARDWARE VER ##
					$vmconfigString .= "<td>".$vm->config->version."</td>";

					## GUEST HOSTNAME ##
					$vmconfigString .= "<td>".($vm->guest->hostName ? $vm->guest->hostName : "N/A")."</td>";

					## UUID ##
					$vmconfigString .= "<td>".($vm->summary->config->uuid ? $vm->summary->config->uuid : "N/A")."</td>";

					## FIRMWARE ##
					if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
						$vmconfigString .= "<td>".($vm->config->firmware ? $vm->config->firmware : "N/A")."</td>";
					} else { $vmconfigString .= "<td>N/A</td>"; }

					## OS ##
					$vmconfigString .= "<td>".($vm->config->guestFullName ? $vm->config->guestFullName : "N/A")."</td>";

					## vCPU ##
					$vmconfigString .= "<td>".($vm->summary->config->numCpu ? $vm->summary->config->numCpu : "N/A")."</td>";
					## vMEM ##
					$vmconfigString .= "<td>".($vm->summary->config->memorySizeMB ? &prettyPrintData($vm->summary->config->memorySizeMB,'M') : "N/A")."</td>";

					## vDISK ##
					$vmconfigString .= "<td>".($vm->summary->config->numVirtualDisks ? $vm->summary->config->numVirtualDisks : "N/A")."</td>";

					## DISK CAPACITY ##
					if($vm->summary->storage) {
						my ($commit,$uncommit) = (0,0);
						if(defined($vm->summary->storage->committed)) { $commit = $vm->summary->storage->committed; }
						if(defined($vm->summary->storage->uncommitted)) { $uncommit = $vm->summary->storage->uncommitted; }
						$vmconfigString .= "<td>".&prettyPrintData(($commit + $uncommit),'B')."</td>";
					} else {
						$vmconfigString .= "<td>N/A</td>";
					}

					## vNIC ##
					$vmconfigString .= "<td>".($vm->summary->config->numEthernetCards ? $vm->summary->config->numEthernetCards : "N/A")."</td>";

					if(!$vm->config->template) {
						## CPU RESERV ##
						$vmconfigString .= "<td>".($vm->summary->config->cpuReservation ? &prettyPrintData($vm->summary->config->cpuReservation,'MHZ') : "N/A")."</td>";

						## MEM RESERV ##
						$vmconfigString .= "<td>".($vm->summary->config->memoryReservation ? &prettyPrintData($vm->summary->config->memoryReservation,'M') : "N/A")."</td>";
					} else {
						$vmconfigString .= "<td>N/A</td>";
						$vmconfigString .= "<td>N/A</td>";
					}

					## TEMPLATE ##
					$vmconfigString .= "<td>".($vm->config->template ? "YES" : "NO")."</td>";

					$vmconfigString .= "</tr>\n";
				}
				######################
				# STATISTICS
				######################
				if($VM_STATS eq "yes") {
					if(!$vm->config->template) {
						$vmstatString .= "<tr>";

						## ESX/ESXi host ##
						$vmstatString .= "<td>".$host_name."</td>";

						## DISPLAY NAME ##
						$vmstatString .= "<td>".$vm->name."</td>";

						## CPU USAGE ##
						$vmstatString .= "<td>".($vm->summary->quickStats->overallCpuUsage ? &prettyPrintData($vm->summary->quickStats->overallCpuUsage,'MHZ') : "N/A" )."</td>";

						## MEM USAGE ##
						$vmstatString .= "<td>".($vm->summary->quickStats->guestMemoryUsage ? &prettyPrintData($vm->summary->quickStats->guestMemoryUsage,'M') : "N/A")."</td>";

						## MAX CPU USAGE ##
						$vmstatString .= "<td>".($vm->runtime->maxCpuUsage ? &prettyPrintData($vm->runtime->maxCpuUsage,'MHZ') : "N/A")."</td>";

						## MAX MEM USAGE ##
						$vmstatString .= "<td>".($vm->runtime->maxMemoryUsage ? &prettyPrintData($vm->runtime->maxMemoryUsage,'M') : "N/A")."</td>";

						## ACTIVE MEM ##
						$vmstatString .= "<td>".($vm->summary->quickStats->guestMemoryUsage ? &prettyPrintData($vm->summary->quickStats->guestMemoryUsage,'M') : "N/A")."</td>";

						## CONSUMED MEM ##
						$vmstatString .= "<td>".($vm->summary->quickStats->hostMemoryUsage ? &prettyPrintData($vm->summary->quickStats->hostMemoryUsage,'M') : "N/A")."</td>";

						## INITIAL MEM RESV OVERHEAD + INITIAL MEM SWAP RESV OVERHEAD ##
						if(($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') && $vm->config->initialOverhead) {
							$vmstatString .= "<td>".($vm->config->initialOverhead->initialMemoryReservation ? &prettyPrintData($vm->config->initialOverhead->initialMemoryReservation,'B') : "N/A")."</td>";
							$vmstatString .= "<td>".($vm->config->initialOverhead->initialSwapReservation ? &prettyPrintData($vm->config->initialOverhead->initialSwapReservation,'B') : "N/A")."</td>";
						} else { $vmstatString .= "<td>N/A</td><td>N/A</td>"; }

						## MEM OVERHEAD ##
						$vmstatString .= "<td>".($vm->summary->quickStats->consumedOverheadMemory ? &prettyPrintData($vm->summary->quickStats->consumedOverheadMemory,'M') : "N/A")."</td>";

						## MEM BALLON ##
						$vmstatString .= "<td>".($vm->summary->quickStats->balloonedMemory ? &prettyPrintData($vm->summary->quickStats->balloonedMemory,'M') : "N/A")."</td>";

						if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
							## COMPRESSED MEM ##
							if(defined($vm->summary->quickStats->compressedMemory)) {
								if($debug) { print "---DEBUG compressedMemory for " . $vm->name . ": \"" . $vm->summary->quickStats->compressedMemory . "\" ---DEBUG\n"; }
								my $compressedMem = "N/A";
								if($vm->summary->quickStats->compressedMemory > 0) {
									$compressedMem = &prettyPrintData($vm->summary->quickStats->compressedMemory,'K');
								}
								$vmstatString .= "<td>".$compressedMem."</td>";
							} else { $vmstatString .= "<td>N/A</td>"; }
						}

						$vmstatString .= "</tr>\n";
					}
				}
				######################
				# VM RESOURCE
				######################
				if($VM_RESOURCE_ALLOCATION eq "yes") {
					if(!$vm->config->template && $vm->resourceConfig) {
						$vmrscString .= "<tr>";

						## ESX/ESXi host ##
						$vmrscString .= "<td>".$host_name."</td>";

						## DISPLAY NAME ##
						$vmrscString .= "<td>".$vm->name."</td>";

						## MODIFIED ##
						$vmrscString .= "<td>".($vm->resourceConfig->lastModified ? $vm->resourceConfig->lastModified : "N/A")."</td>";

						my $cpuAllocation = $vm->resourceConfig->cpuAllocation;
						my $memAllocation = $vm->resourceConfig->memoryAllocation;

						#cpu

						## RESERVATION ##
						$vmrscString .= "<td>".($cpuAllocation->reservation ? &prettyPrintData($cpuAllocation->reservation,'MHZ') : "N/A")."</td>";

						## LIMIT ##
						$vmrscString .= "<td>".($cpuAllocation->limit ? &prettyPrintData($cpuAllocation->limit,'MHZ') : "N/A")."</td>";

						## SHARES ##

						# SHARES VALUE
						$vmrscString .= "<td>".($cpuAllocation->shares->shares ? $cpuAllocation->shares->shares : "N/A")."</td>";

						# SHARES LEVEL
						$vmrscString .= "<td>".($cpuAllocation->shares->level->val ? $cpuAllocation->shares->level->val : "N/A")."</td>";

						## EXPAND RESERVATION ##
						$vmrscString .= "<td>".($cpuAllocation->expandableReservation ? "YES" : "NO")."</td>";

						## OVERHEAD LIMIT ##
						$vmrscString .= "<td>".($cpuAllocation->overheadLimit ? &prettyPrintData($cpuAllocation->overheadLimit,'MHZ') : "N/A")."</td>";

						#mem

						## RESERVATION ##
						$vmrscString .= "<td>".($memAllocation->reservation ? &prettyPrintData($memAllocation->reservation,'M') : "N/A")."</td>";

						## LIMIT ##
						$vmrscString .= "<td>".($memAllocation->limit ? &prettyPrintData($memAllocation->limit,'M') : "N/A")."</td>";

						## SHARES ##

						# SHARES VALUE
						$vmrscString .= "<td>".($memAllocation->shares->shares ? $memAllocation->shares->shares : "N/A")."</td>";

						# SHARES LEVEL
						$vmrscString .= "<td>".($memAllocation->shares->level->val ? $memAllocation->shares->level->val : "N/A")."</td>";

						## EXPAND RESERVATION ##
						$vmrscString .= "<td>".($memAllocation->expandableReservation ? "YES" : "NO")."</td>";

						## OVERHEAD LIMIT ##
						$vmrscString .= "<td>".($memAllocation->overheadLimit ? &prettyPrintData($memAllocation->overheadLimit,'M') : "N/A")."</td>";

						$vmrscString .= "</tr>\n";
					}
				}
				######################
				# VM PERFORMANCE
				######################
				if($VM_PERFORMANCE eq "yes" || $vmperformance eq "yes") {
					if($vm->runtime->powerState->val eq 'poweredOn') {
						my $vmperf = &getCpuAndMemPerf($vm);
						$vmPerfString .= $vmperf;
					}
				}
				######################
				# FT
				######################
				if($VM_FT eq "yes") {
					if(!$vm->config->template && defined($vm->summary->config->ftInfo)) {
						$vmftString .= "<tr>";

						## ESX/ESXi host ##
						$vmftString .= "<td>".$host_name."</td>";

						## DISPLAY NAME ##
						$vmftString .= "<td>".$vm->name."</td>";

						## FT STATE ##
						$vmftString .= "<td>".$vm->runtime->faultToleranceState->val."</td>";

						## FT ROLE ##
						my $role = "";
						if($vm->summary->config->ftInfo->role eq 1) { $role = "PRIMARY"; } else { $role = "SECONDARY"; }
						$vmftString .= "<td>".$role."</td>";

						## FT INSTANCE UUIDS ##
						my $ftuuids = $vm->summary->config->ftInfo->instanceUuids;
						my $instanceuuids = "";
						if($vm->summary->config->ftInfo->role eq 1) {
							$instanceuuids = $ftuuids->[0];
						} else {
							$instanceuuids = $ftuuids->[1];
						}
						$vmftString .= "<td>".$instanceuuids."</td>";

						## FT SECONDARY LATENCY ##
						$vmftString .= "<td>".($vm->summary->quickStats->ftSecondaryLatency ? $vm->summary->quickStats->ftSecondaryLatency : "N/A")."</td>";

						## FT BW ##
						$vmftString .= "<td>".($vm->summary->quickStats->ftLogBandwidth ? $vm->summary->quickStats->ftLogBandwidth : "N/A")."</td>";
						$vmftString .= "</tr>\n";
					}
				}
				######################
				# EZT
				######################
				if($VM_EZT eq "yes" && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
					if(!$vm->config->template) {
						my $devices = $vm->config->hardware->device;
						my ($ezt_disk_string,$ezt_size_string,$ezt_label_string) = ("","","");
						my $hasEZT = 0;
						foreach(@$devices) {
							if($_->isa('VirtualDisk') && $_->backing->isa('VirtualDiskFlatVer2BackingInfo')) {
								my $diskName = $_->backing->fileName;
								my $label = ($_->deviceInfo->label ? $_->deviceInfo->label : "N/A");
								if(!$_->backing->thinProvisioned && defined($_->backing->eagerlyScrub)) {
									if($_->backing->eagerlyScrub) {
										$hasEZT = 1;
										$ezt_label_string .= $label."<br/>";
										$ezt_disk_string .= $diskName."<br/>";
										$ezt_size_string .= &prettyPrintData($_->capacityInKB,'K')."<br/>";
									}
								}
							}
						}
						if($hasEZT eq 1) {
							$vmeztString .= "<tr>";

							## ESX/ESXi host ##
							$vmeztString .= "<td>".$host_name."</td>";

							## DISPLAY NAME ##
							$vmeztString .= "<td>".$vm->name."</td>";

							## EZT LABEL ##
							$vmeztString .= "<td>".$ezt_label_string."</td>";

							## EZT DISKS ##
							$vmeztString .= "<td>".$ezt_disk_string."</td>";

							## EZT DISKS SIZE ##
							$vmeztString .= "<td>".$ezt_size_string."</td>";

							$vmeztString .= "</tr>\n";
						}
					}
				}
				######################
				# THIN
				######################
				if($VM_THIN eq "yes") {
					if(!$vm->config->template) {
						my $devices = $vm->config->hardware->device;
						my ($thin_disk_string,$thin_size_string,$thin_label_string) = ("","","");
						my $hasThin = 0;
						foreach(@$devices) {
							if($_->isa('VirtualDisk') && $_->backing->isa('VirtualDiskFlatVer2BackingInfo')) {
								my $diskName = $_->backing->fileName;
								my $label = ($_->deviceInfo->label ? $_->deviceInfo->label : "N/A");
								if($_->backing->thinProvisioned) {
									$hasThin = 1;
									$thin_label_string .= $label."<br/>";
									$thin_disk_string .= $diskName."<br/>";
									$thin_size_string .= &prettyPrintData($_->capacityInKB,'K')."<br/>";
								}
							}
						}
						if($hasThin eq 1) {
							$vmthinString .= "<tr>";

							## ESX/ESXi host ##
							$vmthinString .= "<td>".$host_name."</td>";

							## DISPLAY NAME ##
							$vmthinString .= "<td>".$vm->name."</td>";

							## THIN LABEL ##
							$vmthinString .= "<td>".$thin_label_string."</td>";

							## THIN DISKS ##
							$vmthinString .= "<td>".$thin_disk_string."</td>";

							## THIN DISKS SIZE ##
							$vmthinString .= "<td>".$thin_size_string."</td>";

							$vmthinString .= "</tr>\n";
						}
					}
				}
				######################
				# DEVICE
				######################
				if($VM_DEVICE eq "yes") {
					if(!$vm->config->template) {
						$vmdeviceString .= "<tr>";

						## ESX/ESXi host ##
						$vmdeviceString .= "<td>".$host_name."</td>";

						## DISPLAY NAME ##
						$vmdeviceString .= "<td>".$vm->name."</td>";

						my %deviceMapper = ();

						my $devices = $vm->config->hardware->device;
						#foreach(@$devices) {
						#	$deviceMapper{$_->key} = $_->deviceInfo->label;
						#}

						my ($cdrom,$idecontroller,$pcicontroller,$ps2controller,$paracontroller,$buscontroller,$lsicontroller,$lsilogiccontroller,$siocontroller,$usbcontroller,$disk,$e1000ethernet,$pcnet32ethernet,$vmxnet2ethernet,$vmxnet3ethernet,$floppy,$keyboard,$videocard,$vmci,$vmi,$parallelport,$pcipassthrough,$pointingdevice,$scsipassthrough,$serialport,$ensoniqsoundcard,$blastersoundcard,$usb) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);

						foreach my $device (@$devices) {
							if($device->isa('VirtualCdrom')) {
								$cdrom++;
							}elsif($device->isa('VirtualController')) {
								if($device->isa('VirtualIDEController')) {
									$idecontroller++;
								}elsif($device->isa('VirtualPCIController')) {
									$pcicontroller++;
								}elsif($device->isa('VirtualPS2Controller')) {
									$ps2controller++;
								}elsif($device->isa('VirtualSCSIController')) {
									if($device->isa('ParaVirtualSCSIController')) {
										$paracontroller++;
									}elsif($device->isa('VirtualBusLogicController')) {
										$buscontroller++;
									}elsif($device->isa('VirtualLsiLogicController')) {
										$lsicontroller++;
									}elsif($device->isa('VirtualLsiLogicSASController')) {
										$lsilogiccontroller++;
									}
								}elsif($device->isa('VirtualSIOController')) {
									$siocontroller++;
								}elsif($device->isa('VirtualUSBController')) {
									$usbcontroller++;
								}
							}elsif($device->isa('VirtualDisk')) {
								$disk++;
							}elsif($device->isa('VirtualEthernetCard')) {
								if($device->isa('VirtualE1000')) {
									$e1000ethernet++;
								}elsif($device->isa('VirtualPCNet32')) {
									$pcnet32ethernet++;
								}elsif($device->isa('VirtualVmxnet')) {
									if($device->isa('VirtualVmxnet2')) {
										$vmxnet2ethernet++;
									}elsif($device->isa('VirtualVmxnet3')) {
										$vmxnet3ethernet++;
									}
								}
							}elsif($device->isa('VirtualFloppy')) {
								$floppy++;
							}elsif($device->isa('VirtualKeyboard')) {
								$keyboard++;
							}elsif($device->isa('VirtualMachineVideoCard')) {
								$videocard++;
							}elsif($device->isa('VirtualMachineVMCIDevice')) {
								$vmci++;
							}elsif($device->isa('VirtualMachineVMIROM')) {
								$vmi++;
							}elsif($device->isa('VirtualParallelPort')) {
								$parallelport++;
							}elsif($device->isa('VirtualPCIPassthrough')) {
								$pcipassthrough++;
							}elsif($device->isa('VirtualPointingDevice')) {
								$pointingdevice++;
							}elsif($device->isa('VirtualSCSIPassthrough')) {
								$scsipassthrough++;
							}elsif($device->isa('VirtualSerialPort')) {
								$serialport++;
							}elsif($device->isa('VirtualSoundCard')) {
								if($device->isa('VirtualEnsoniq1371')) {
									$ensoniqsoundcard++;
								}elsif($device->isa('VirtualSoundBlaster16')) {
									$blastersoundcard++;
								}
							}elsif($device->isa('VirtualUSB')) {
								$usb++;
							}
						}

						## OS ##
						$vmdeviceString .= "<td>".($vm->config->guestFullName ? $vm->config->guestFullName : "N/A")."</td>";

						## CDROM ##
						$vmdeviceString .= "<td>".$cdrom."</td>";

						## CONTROLER ##
						my $controllerString = "";
						if($idecontroller != 0) {
							$controllerString .= $idecontroller . " x IDE Controller<br/>";
						}
						if($pcicontroller != 0) {
							$controllerString .= $pcicontroller . " x PCI Controller<br/>";
						}
						if($ps2controller != 0) {
							$controllerString .= $ps2controller . " x PS2 Controller<br/>";
						}
						if($paracontroller != 0) {
							$controllerString .= $paracontroller . " x PARA-VIRT Controller<br/>";
						}
						if($buscontroller != 0) {
							$controllerString .= $buscontroller . " x BUS Controller<br/>";
						}
						if($lsicontroller != 0) {
							$controllerString .= $lsicontroller . " x LSI LOGIC Controller<br/>";
						}
						if($lsilogiccontroller != 0) {
							$controllerString .= $lsilogiccontroller . " x LSI LOGIC SAS Controller<br/>";
						}
						if($siocontroller != 0) {
							$controllerString .= $siocontroller . " x SIO Controller<br/>";
						}
						if($usbcontroller != 0) {
							$controllerString .= $usbcontroller . " x USB Controller<br/>";
						}
						if($controllerString eq "") { $controllerString = "N/A"; }
						$vmdeviceString .= "<td>".$controllerString."</td>";

						## DISK ##
						$vmdeviceString .= "<td>".$disk."</td>";

						## ETHERNET CARD ##
						my $ethString = "";
						if($e1000ethernet != 0) {
							$ethString .= $e1000ethernet . " x e1000<br/>";
						}
						if($pcnet32ethernet != 0) {
							$ethString .= $pcnet32ethernet . " x PCNET32<br/>";
						}
						if($vmxnet2ethernet != 0) {
							$ethString .= $vmxnet2ethernet . " x VMXNET2<br/>";
						}
						if($vmxnet3ethernet != 0) {
							$ethString .= $vmxnet3ethernet . " x VMXNET3<br/>";
						}
						if($ethString eq "") { $ethString = "N/A"; }
						$vmdeviceString .= "<td>".$ethString."</td>";

						## FLOPPY ##
						$vmdeviceString .= "<td>".$floppy."</td>";

						## KEYBOARD ##
						$vmdeviceString .= "<td>".$keyboard."</td>";

						## VIDEO CARD ##
						$vmdeviceString .= "<td>".$videocard."</td>";

						## VMCI ##
						$vmdeviceString .= "<td>".$vmci."</td>";

						## VMIROM ##
						$vmdeviceString .= "<td>".$vmi."</td>";

						## PARALLEL PORT ##
						$vmdeviceString .= "<td>".$parallelport."</td>";

						## PCI PASS THROUGH ##
						$vmdeviceString .= "<td>".$pcipassthrough."</td>";

						## POINTING DEVICE ##
						$vmdeviceString .= "<td>".$pointingdevice."</td>";

						## SCSI PASS THROUGH ##
						$vmdeviceString .= "<td>".$scsipassthrough."</td>";

						## SERIAL PORT ##
						$vmdeviceString .= "<td>".$serialport."</td>";

						## SOUND CARD ##
						my $soundString = "";
						if($ensoniqsoundcard != 0) {
							$soundString .= $ensoniqsoundcard . " x Ensoiq1373 Sound Card<br/>";
						}
						if($blastersoundcard != 0) {
							$soundString .= $blastersoundcard . " x Soundblaster Sound Card<br/>";
						}
						if($soundString eq "") { $soundString = "N/A"; }
						$vmdeviceString .= "<td>".$soundString."</td>";

						## USB ##
						$vmdeviceString .= "<td>".$usb."</td>";

						$vmdeviceString .= "</tr>\n";
					}
				}
				######################
				# VM STORAGE
				######################
				if($VM_STORAGE eq "yes") {
					if(!$vm->config->template && $vm->guest->disk) {
						$vmstorageString .= "<tr>";

						## ESX/ESXi host ##
						$vmstorageString .= "<td>".$host_name."</td>";

						## DISPLAY NAME ##
						$vmstorageString .= "<td>".$vm->name."</td>";

						my $vdisks = $vm->guest->disk;
						my $disk_string = "";
						foreach my $disk (@$vdisks) {
							my $vm_disk_path = $disk->diskPath;
							my $vm_disk_free = prettyPrintData($disk->freeSpace,'B');
							my $vm_disk_cap = prettyPrintData($disk->capacity,'B');
							my ($vm_perc_free, $perc_string) = ();
							# If the disk is not mounted by the VM, it will show a zero capacity, leading to divide by zero crash when calculating the percent free.
							if ($disk->capacity != 0) {
								$vm_perc_free = &restrict_num_decimal_digits((($disk->freeSpace / $disk->capacity) * 100),2);
								$perc_string = getColor($vm_perc_free);
							} else {
								$vm_perc_free = "NaN";
								$perc_string = "<td bgcolor=\"$red\">NaN %</td>";
							}
							$disk_string .= "<td><table border=\"1\" width=100%><tr><td>$vm_disk_path</td><td>$vm_disk_free</td><td>$vm_disk_cap</td>$perc_string</tr></table></td>";
						}
						$vmstorageString .= $disk_string;
						$vmstorageString .= "</tr>\n";
					}
				}
				######################
				# VM NETWORK
				######################
				if($VM_NETWORK eq "yes" && $vm->guest->net) {
					if(!$vm->config->template) {
						$vmnetworkString .= "<tr>";

						## ESX/ESXi host ##
						$vmnetworkString .= "<td>".$host_name."</td>";

						## DISPLAY NAME ##
						$vmnetworkString .= "<td>".$vm->name."</td>";

						my ($vm_ip_string,$vm_mac_string,$vm_pg_string,$vm_connect_string) = ("","","","");

						my $vnics = $vm->guest->net;
						foreach(@$vnics) {
							## IP ADDRESS ##
							if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
								if($_->ipConfig) {
									my $ips = $_->ipConfig->ipAddress;
									foreach(@$ips) {
										if($demo eq "no") {
											$vm_ip_string .= $_->ipAddress."<br/>";
										} else {
											$vm_ip_string .= "demo_mode<br/>";
										}
									}
								} else { $vm_ip_string .= "N/A<br/>"; }
							} else {
								if($_->ipAddress) {
									my $ips = $_->ipAddress;
									foreach(@$ips) {
										if($demo eq "no") {
											$vm_ip_string .= $_."<br/>";
										} else {
											$vm_ip_string .= "demo_mode<br/>";
										}
									}
								} else {
									$vm_ip_string .= "N/A<br/>";
								}
							}

							## MAC ADDRESS ##
							if($_->macAddress) {
								if($demo eq "no") {
									$vm_mac_string .= $_->macAddress."<br/>";
								} else {
									$vm_mac_string .= "demo_mode<br/>";
								}
							} else {
								$vm_mac_string .= "N/A<br/>";
							}

							## PORTGROUP ##
							if($_->network) {
								if($demo eq "no") {
									$vm_pg_string .= $_->network."<br/>";
								} else {
									$vm_pg_string .= "demo_mode<br/>";
								}
							} else {
								$vm_pg_string .=  "N/A<br/>";
							}

							## CONNECTED ##
							$vm_connect_string .= ($_->connected ? "YES<br/>" : "NO<br/>");
						}
						$vmnetworkString .= "<td>".$vm_ip_string."</td><td>".$vm_mac_string."</td><td>".$vm_pg_string."</td><td>".$vm_connect_string."</td>";
						$vmnetworkString .= "</tr>\n";
					}
				}
				######################
				# SNAPSHOT
				######################
				if($VM_SNAPSHOT eq "yes") {
					if(!$vm->config->template) {
						if($vm->snapshot) {
							&getSnapshotTree($host_name,$vm->name,$vm->snapshot->currentSnapshot,$vm->snapshot->rootSnapshotList);
							foreach(@vmsnapshots) {
								$vmsnapString .= "<tr>".$_."</tr>\n";
							}
							@vmsnapshots = ();
						}
					}
				}
				######################
				# CDROM
				######################
				if($VM_CDROM eq "yes") {
					if(!$vm->config->template) {
						my $devices = $vm->config->hardware->device;
						my ($cd_string) = ("");
						my $hasCD = 0;
						foreach(@$devices) {
							if($_->isa('VirtualCdrom') && $_->connectable->connected) {
								$hasCD = 1;
								if($_->deviceInfo->summary) {
									$cd_string .= $_->deviceInfo->summary."<br/>";
								} else {
									$cd_string .= "N/A";
								}
							}
						}
						if($hasCD eq 1) {
							$vmcdString .= "<tr>";

							## ESX/ESXi host ##
							$vmcdString .= "<td>".$host_name."</td>";

							## DISPLAY NAME ##
							$vmcdString .= "<td>".$vm->name."</td>";

							## ISO ##
							$vmcdString .= "<td>".$cd_string."</td>";

							$vmcdString .= "</tr>\n";
						}

					}
				}
				######################
				# FLOPPY
				######################
				if($VM_FLOPPY eq "yes") {
					if(!$vm->config->template) {
						my $devices = $vm->config->hardware->device;
						my ($flp_string) = ("");
						my $hasFLP = 0;
						foreach(@$devices) {
							if($_->isa('VirtualFloppy') && $_->connectable->connected) {
								$hasFLP = 1;
								if($_->deviceInfo->summary) {
									$flp_string .= $_->deviceInfo->summary."<br/>";
								} else {
									$flp_string .= "N/A";
								}
							}
						}
						if($hasFLP eq 1) {
							$vmflpString .= "<tr>";

							## ESX/ESXi host ##
							$vmflpString .= "<td>".$host_name."</td>";

							## DISPLAY NAME ##
							$vmflpString .= "<td>".$vm->name."</td>";

							## FLP ##
							$vmflpString .= "<td>".$flp_string."</td>";

							$vmflpString .= "</tr>\n";
						}
					}
				}
				######################
				# TOOLS
				######################
				if($VM_TOOL eq "yes") {
					if(!$vm->config->template) {
						$vmtoolString .= "<tr>";

						## ESX/ESXi host ##
						$vmtoolString .= "<td>".$host_name."</td>";

						## DISPLAY NAME ##
						$vmtoolString .= "<td>".$vm->name."</td>";

						if($vm->guest) {
							## TOOLS VERSION ##
							$vmtoolString .= "<td>".($vm->guest->toolsVersion ? $vm->guest->toolsVersion : "N/A")."</td>";

							## TOOLS RUNNING STATUS ##
							$vmtoolString .= "<td>".($vm->guest->toolsRunningStatus ? $vm->guest->toolsRunningStatus : "N/A")."</td>";
							## TOOLS VERSION STATUS ##
							if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
								$vmtoolString .= "<td>".($vm->guest->toolsVersionStatus2 ? $vm->guest->toolsVersionStatus2 : "N/A")."</td>";
							} else {
								$vmtoolString .= "<td>".($vm->guest->toolsVersionStatus ? $vm->guest->toolsVersionStatus : "N/A")."</td>";
							}
						} else {
							$vmtoolString .= "<td>N/A</td>";
							$vmtoolString .= "<td>N/A</td>";
							$vmtoolString .= "<td>N/A</td>";
						}
						if($vm->config->tools) {
							## TOOLS UPGRADE POLICY ##
							$vmtoolString .= "<td>".($vm->config->tools->toolsUpgradePolicy ? $vm->config->tools->toolsUpgradePolicy : "N/A")."</td>";

							## SYNC TIME ##
							$vmtoolString .= "<td>".($vm->config->tools->syncTimeWithHost ? "YES" : "NO")."</td>";
						} else {
							$vmtoolString .= "<td>N/A</td>";
							$vmtoolString .= "<td>N/A</td>";
						}
						$vmtoolString .= "</tr>\n";
					}
				}
				######################
				# RDM
				######################
				if($VM_RDM eq "yes") {
					if(!$vm->config->template) {
						my $devices = $vm->config->hardware->device;
						my $hasRDM = 0;
						foreach(@$devices) {
							my ($rdm_string) = ("");
							if($_->isa('VirtualDisk') && ($_->backing->isa('VirtualDiskRawDiskVer2BackingInfo') || $_->backing->isa('VirtualDiskRawDiskMappingVer1BackingInfo'))) {
								$hasRDM = 1;
								my $compat_mode = ($_->backing->compatibilityMode ? $_->backing->compatibilityMode : "N/A");
								my $vmhba = ($_->backing->deviceName ? $_->backing->deviceName : "N/A");
								my $disk_mode = ($_->backing->diskMode ? $_->backing->diskMode : "N/A");
								my $lun_uuid = ($_->backing->lunUuid ? $_->backing->lunUuid : "N/A");
								my $vm_uuid = ($_->backing->uuid ? $_->backing->uuid : "N/A");
								$rdm_string .= "<td>".$compat_mode."</td><td>".$vmhba."</td><td>".$disk_mode."</td><td>".$lun_uuid."</td><td>".$vm_uuid."</td>";

						#}
						#if($hasRDM eq 1) {
							$vmrdmString .= "<tr>";

							## ESX/ESXi host ##
							$vmrdmString .= "<td>".$host_name."</td>";

							## DISPLAY NAME ##
							$vmrdmString .= "<td>".$vm->name."</td>";

							## RDM ##
							$vmrdmString .= $rdm_string;

							$vmrdmString .= "</tr>\n";
						}}
					}
				}
				######################
				# NPIV
				######################
				if($VM_NPIV eq "yes") {
					if(!$vm->config->template) {
						if($vm->config->npivNodeWorldWideName && $vm->config->npivPortWorldWideName) {
							$vmnpivString .= "<tr>";

							## ESX/ESXi host ##
							$vmnpivString .= "<td>".$host_name."</td>";

							## DISPLAY NAME ##
							$vmnpivString .= "<td>".$vm->name."</td>";

							my $nwwns = $vm->config->npivNodeWorldWideName;
							my $pwwns = $vm->config->npivPortWorldWideName;
							my $type = ($vm->config->npivWorldWideNameType ? $vm->config->npivWorldWideNameType : "N/A");
							my $desirednwwn = ($vm->config->npivDesiredNodeWwns ? $vm->config->npivDesiredNodeWwns : "N/A");
							my $desiredpwwn = ($vm->config->npivDesiredPortWwns ? $vm->config->npivDesiredPortWwns : "N/A");
							my $npiv_string = "<td>";
							foreach(@$nwwns) {
								my $nwwn = (Math::BigInt->new($_))->as_hex();
								$nwwn =~ s/^..//;
								$nwwn = join(':', unpack('A2' x 8, $nwwn));
								if($demo eq "no") {
									$npiv_string .= "$nwwn<br/>";
								} else {
									$npiv_string .= "XX:XX:XX:XX:XX:XX:XX:XX<br/>";
								}
							}
							$npiv_string .= "</td><td>";
							foreach(@$pwwns) {
								my $pwwn = (Math::BigInt->new($_))->as_hex();
								$pwwn =~ s/^..//;
								$pwwn = join(':', unpack('A2' x 8, $pwwn));
								if($demo eq "no") {
									$npiv_string .= "$pwwn<br/>";
								} else {
									$npiv_string .= "XX:XX:XX:XX:XX:XX:XX:XX<br/>";
								}
							}
							my $npivtype = "";
							if($type eq "vc") { $npivtype = "Virtual Center"; }
							elsif($type eq "external") { $npivtype = "External Source"; }
							elsif($type eq "host") { $npivtype = "ESX or ESXi"; }
							$npiv_string .= "</td><td>".$npivtype."</td><td>".$desirednwwn."</td><td>".$desiredpwwn."</td>";

							$vmnpivString .= $npiv_string;
							$vmnpivString .= "</tr>\n";
						}
					}
				}


				if($VM_STATS eq "yesaaaaa") {
					if(!$vm->config->template) {
						$vmstatString .= "<tr>";

						## ESX/ESXi host ##
						$vmstatString .= "<td>".$host_name."</td>";

						## DISPLAY NAME ##
						$vmstatString .= "<td>".$vm->name."</td>";


						$vmstatString .= "</tr>\n";
					}
				}

				## STOP ###
			}
		}

		######################
		# DLETA
		######################
		if($VM_DELTA eq "yes") {
			foreach(@vmdeltas) {
				$vmdeltaString .= "<tr>".$_."</tr>\n";
			}
			@vmdeltas = ();
		}
		&buildVMReport($cluster_name,$cluster_count,$type,$atype,$aversion);
	}
}

sub printHostSummary {
	my ($local_hosts,$cluster_name,$cluster_count,$type,$atype,$aversion,$sc) = @_;

	if(@$local_hosts) {
		foreach my $local_host(sort {$a->summary->config->name cmp $b->summary->config->name} @$local_hosts) {
			if($demo eq "no") {
				$host_name = $local_host->name;
			}

			#skip if host is not accessible
			next if($local_host->runtime->connectionState->val ne "connected");

			#skip if VM is not in valid list
			if($hostlist) {
				next if(!$hostlists{$local_host->name});
			}

			#capture unique hosts for later use
			push @hosts_seen,$host_name;

			#host api version
			my $hostAPIVersion = $local_host->config->product->version;

			######################
			# HARDWARE
			######################
			if($HOST_HARDWARE_CONFIGURATION eq "yes") {
				$hardwareConfigurationString .= "<tr>";
				$hardwareConfigurationString .= "<td>".$host_name."</td>";
				$hardwareConfigurationString .= "<td>".$local_host->summary->hardware->vendor."</td>";

				my $additional_vendor_info = "";
				if($local_host->summary->hardware->otherIdentifyingInfo) {
					my $add_info = $local_host->summary->hardware->otherIdentifyingInfo;
					foreach (@$add_info) {
						$additional_vendor_info .= $_->identifierType->key.": ".$_->identifierValue." ";
					}
					if($additional_vendor_info eq '') {
						$additional_vendor_info = "UNKNOWN";
					}
				}
				$hardwareConfigurationString .= "<td>".$additional_vendor_info."</td>";
				$hardwareConfigurationString .= "<td>".$local_host->summary->hardware->model."</td>";
				$hardwareConfigurationString .= "<td>".$local_host->summary->hardware->cpuModel."</td>";
				if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
					$hardwareConfigurationString .= "<td>".(($local_host->hardware->smcPresent) ? "YES" : "NO")."</td>";
				} else { $hardwareConfigurationString .= "<td>N/A</td>"; }
				$hardwareConfigurationString .= "<td>".(($local_host->config->hyperThread->available) ? "YES" : "NO")."</td>";
				$hardwareConfigurationString .= "<td>".prettyPrintData($local_host->summary->hardware->numCpuCores*$local_host->summary->hardware->cpuMhz,'MHZ')."</td>";
				$hardwareConfigurationString .= "<td>".prettyPrintData($local_host->summary->quickStats->overallCpuUsage,'MHZ')."</td>";
				$hardwareConfigurationString .= "<td>".$local_host->summary->hardware->numCpuPkgs."</td>";
				$hardwareConfigurationString .= "<td>".($local_host->summary->hardware->numCpuCores/$local_host->summary->hardware->numCpuPkgs)."</td>";
				$hardwareConfigurationString .= "<td>".$local_host->summary->hardware->numCpuThreads."</td>";
				$hardwareConfigurationString .= "<td>".prettyPrintData($local_host->summary->hardware->memorySize,'B')."</td>";
				$hardwareConfigurationString .= "<td>".prettyPrintData($local_host->summary->quickStats->overallMemoryUsage,'M')."</td>";
				$hardwareConfigurationString .= "<td>".$local_host->summary->hardware->numNics."</td>";
				$hardwareConfigurationString .= "<td>".$local_host->summary->hardware->numHBAs."</td>";
				$hardwareConfigurationString .= "</tr>\n";
			}
			######################
			# MGMT
			######################
			if($HOST_MGMT eq "yes") {
				$mgmtString .= "<tr>";

				$mgmtString .= "<td>".$host_name."</td>";

				my $mgmtIp = "N/A";
				if($local_host->summary->managementServerIp) {
					if($demo eq "no") {
						my ($ipaddress,$dnsname) = ("N/A","N/A");
						eval {
							$ipaddress = inet_aton($local_host->summary->managementServerIp);
							if($debug) { print "---DEBUG managementServerIp: " . $local_host->summary->managementServerIp . " ---\n"; }
							$dnsname = gethostbyaddr($ipaddress, AF_INET);
							if(!defined($dnsname)) {
								$dnsname = "N/A";
							}
							if($debug) { print "---DEBUG dnsname: " . $dnsname . " ---\n"; }
						};
						if(!$@) {
							$mgmtIp = $local_host->summary->managementServerIp . " ( $dnsname )";
						} else {
							$mgmtIp = $local_host->summary->managementServerIp . " ( UNKNOWN )";
						}
					} else {
						$mgmtIp = "demo_mode";
					}
				}

				$mgmtString .= "<td>".$mgmtIp."</td>";

				if($atype eq "VirtualCenter") {
					if($local_host->summary->config->product) {
						$mgmtString .= "<td>".($local_host->config->adminDisabled ? "YES" : "NO")."</td>";
					}
				} else {
					$mgmtString .= "<td>UNKNOWN</td>";
				}

				if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
					if($hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
						my $systemFile = "";
						if($local_host->config->systemFile) {
							my $systemfile = $local_host->config->systemFile;
							foreach(@$systemfile) {
								$systemFile .= $_ . "<br/>";
							}
						} else {
							$systemFile = "N/A";
						}
						$mgmtString .= "<td>$systemFile</td>";
					} else {
						$mgmtString .= "<td>N/A</td>";
					}
				}

				$mgmtString .= "<td>".$local_host->summary->hardware->uuid."</td>";
				if($local_host->config->consoleReservation) {
					$mgmtString .= "<td>".($local_host->config->consoleReservation->serviceConsoleReserved ? &prettyPrintData($local_host->config->consoleReservation->serviceConsoleReserved,'B') : "N/A")."</td>";
				} else {
					$mgmtString .= "<td>N/A</td>";
				}

				$mgmtString .= "</tr>\n";
			}
			######################
			# STATE
			######################
			if($HOST_STATE eq "yes") {
				$stateString .= "<tr>";
				$stateString .= "<td>".$host_name."</td>";
				my $host_health .= $local_host->overallStatus->val;
				if ($host_health eq 'green') { $stateString .= "<td bgcolor=\"$green\">HOST is OK</td>"; }
				elsif ($host_health eq 'red') { $stateString .= "<td bgcolor=\"$red\">HOST has a problem</td>"; }
				elsif ($host_health eq 'yellow') { $stateString .= "<td bgcolor=\"$yellow\">HOST might have a problem</td>"; }
				else { $stateString .= "<td bgcolor=\"gray\">UNKNOWN</td>"; }
				$stateString .= "<td>".$local_host->runtime->powerState->val."</td>";
				if($local_host->runtime->bootTime) { $stateString .= "<td>".$local_host->runtime->bootTime."</td>"; }
				else { $stateString .= "<td>UNKNOWN</td>"; }

				if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
					if($hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
						if($local_host->summary->quickStats->uptime) {
							my $uptime = $local_host->summary->quickStats->uptime;
							$stateString .= "<td>".&getUptime($uptime)."</td>";
						}
						else { $stateString .= "<td>UNKNOWN</td>"; }
					} else {
						$stateString .= "<td>N/A</td>";
					}
				}

				if(($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') && $atype eq "VirtualCenter") {
					if($local_host->runtime->dasHostState) {
						$stateString .= "<td>".$local_host->runtime->dasHostState->state."</td>";
					} else {
						$stateString .= "<td>N/A</td>";
					}
				} else {
					$stateString .= "<td>N/A</td>";
				}

				$stateString .= "<td>".$local_host->runtime->connectionState->val."</td>";
				$stateString .= "<td>".(($local_host->summary->runtime->inMaintenanceMode) ? "YES" : "NO")."</td>";

				if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
					if($hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
						$stateString .= "<td>".(($local_host->runtime->standbyMode) ? $local_host->runtime->standbyMode : "N/A")."</td>";
					} else {
						$stateString .= "<td>N/A</td>";
					}
				}

				$stateString .= "<td>".(($local_host->summary->config->vmotionEnabled) ? "YES" : "NO")."</td>";
				$stateString .= "<td>".${$local_host->summary->config->product}{'fullName'}."</td>";
				$stateString .= "</tr>\n";
			}
			######################
			# HEALTH
			######################
			if($HOST_HEALTH eq "yes") {
				if($local_host->runtime->healthSystemRuntime) {
					if($local_host->runtime->healthSystemRuntime->hardwareStatusInfo) {
						my $hardwareStatusInfo = $local_host->runtime->healthSystemRuntime->hardwareStatusInfo;
						my ($cpuInfo,$memInfo,$storageInfo);
						$healthHardwareString .= "<tr><th align=\"left\">".$host_name."</th></tr>\n";
						my ($sensor_health_color,$sensor_health) = ("","");;

						if($hardwareStatusInfo->cpuStatusInfo) {
							$cpuInfo = $hardwareStatusInfo->cpuStatusInfo;
							foreach(@$cpuInfo) {
								$sensor_health = $_->status->key;
								if ($sensor_health =~ m/green/i) { $sensor_health_color="<td bgcolor=\"$green\">OK</td>"; }
								elsif ($sensor_health_color =~ m/red/i) { $sensor_health_color="<td bgcolor=\"$red\">PROBLEM</td>"; }
								elsif ($sensor_health_color =~ m/yellow/i) { $sensor_health_color="<td bgcolor=\"$yellow\">WARNING</td>"; }
								else { $sensor_health_color="<td bgcolor=\"gray\">UNKNOWN</td>"; }
								$healthHardwareString .= "<tr><td>".$_->name."</td>".$sensor_health_color."</tr>\n";
							}
						}
						if($hardwareStatusInfo->memoryStatusInfo) {
							$memInfo = $hardwareStatusInfo->memoryStatusInfo;
							foreach(@$memInfo) {
								$sensor_health = $_->status->key;
								if ($sensor_health =~ m/green/i) { $sensor_health_color="<td bgcolor=\"$green\">OK</td>"; }
								elsif ($sensor_health_color =~ m/red/i) { $sensor_health_color="<td bgcolor=\"$red\">PROBLEM</td>"; }
								elsif ($sensor_health_color =~ m/yellow/i) { $sensor_health_color="<td bgcolor=\"$yellow\">WARNING</td>"; }
								else { $sensor_health_color="<td bgcolor=\"gray\">UNKNOWN</td>"; }
								$healthHardwareString .= "<tr><td>".$_->name."</td>".$sensor_health_color."</tr>\n";
							}
						}
						if($hardwareStatusInfo->storageStatusInfo) {
							$storageInfo = $hardwareStatusInfo->storageStatusInfo;
							foreach(@$storageInfo) {
								$sensor_health = $_->status->key;
								if ($sensor_health =~ m/green/i) { $sensor_health_color="<td bgcolor=\"$green\">OK</td>"; }
								elsif ($sensor_health_color =~ m/red/i) { $sensor_health_color="<td bgcolor=\"$red\">PROBLEM</td>"; }
								elsif ($sensor_health_color =~ m/yellow/i) { $sensor_health_color="<td bgcolor=\"$yellow\">WARNING</td>"; }
								else { $sensor_health_color="<td bgcolor=\"gray\">UNKNOWN</td>"; }
								$healthHardwareString .= "<tr><td>".$_->name."</td>".$sensor_health_color."</tr>\n";
							}
						}
					}
					if($local_host->runtime->healthSystemRuntime->systemHealthInfo) {
						my $sensors = $local_host->runtime->healthSystemRuntime->systemHealthInfo->numericSensorInfo;
						$healthSoftwareString .= "<tr><th align=\"left\">".$host_name."</th></tr>\n";
						my $sensor_health_color = "";
						foreach(sort {$a->name cmp $b->name} @$sensors) {
							my $sensor_health = $_->healthState->key;
							if ($sensor_health =~ m/green/) { $sensor_health_color="<td bgcolor=\"$green\">OK</td>"; }
							elsif ($sensor_health_color =~ m/red/) { $sensor_health_color="<td bgcolor=\"$red\">PROBLEM</td>"; }
							elsif ($sensor_health_color =~ m/yellow/) { $sensor_health_color="<td bgcolor=\"$yellow\">WARNING</td>"; }
							else { $sensor_health_color="<td bgcolor=\"gray\">UNKNOWN</td>"; }

							my $reading;
							if(defined($_->rateUnits)) {
								$reading =  &restrict_num_decimal_digits(($_->currentReading * (10 ** $_->unitModifier)),3) . " " . $_->baseUnits . "/" . $_->rateUnits;
							} else {
								$reading =  &restrict_num_decimal_digits(($_->currentReading * (10 ** $_->unitModifier)),3) . " " . $_->baseUnits;
							}
							$healthSoftwareString .= "<tr><td>".$_->name."</td><td>".$reading."</td>".$sensor_health_color."</tr>\n";
						}
					}
				}
			}
			######################
			# PERFORMANCE
			######################
			if($HOST_PERFORMANCE eq "yes" || $hostperformance eq "yes") {
				my $hostperf = &getCpuAndMemPerf($local_host);
				$hostPerfString .= $hostperf;
			}
			######################
			# NIC
			######################
			if($HOST_NIC eq "yes") {
				my $nics = $local_host->config->network->pnic;
				foreach my $nic (@$nics) {
					$nicString .= "<tr><td>".$host_name."</td>";
					$nicString .= "<td>".$nic->device."</td><td>".$nic->pci."</td><td>".$nic->driver."</td>";
					if($nic->linkSpeed) {
						$nicString .= "<td>".(($nic->linkSpeed->duplex) ? "FULL DUPLEX" : "HALF-DUPLEX")."</td><td>".$nic->linkSpeed->speedMb." MB</td>";
					} else {
						$nicString .= "<td>UNKNOWN</td><td>UNKNOWN</td>";
					}
					$nicString .= "<td>".(($nic->wakeOnLanSupported) ? "YES" : "NO")."</td>";
					if($demo eq "no") {
						$nicString .= "<td>".$nic->mac."</td></tr>\n";
					} else {
						$nicString .= "<td>demo_mode</td></tr>\n";
					}
				}
			}
			######################
			# HBA
			######################
			if($HOST_HBA eq "yes") {
				my $hbas;
				eval { $hbas = $local_host->config->storageDevice->hostBusAdapter; };
				if(!$@) {
					foreach my $hba (@$hbas) {
						$hbaString .= "<tr><td>".$host_name."</td>";
						if($hba->isa("HostFibreChannelHba")) {
							my $hbaType = "FC";
							my ($fcfMac,$vnportMac) = ("","");
							if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
								if($hba->isa("HostFibreChannelOverEthernetHba")) {
									$hbaType = "FCoE";
									$fcfMac = $hba->linkInfo->fcfMac;
									$vnportMac = $hba->linkInfo->vnportMac;
								}
							}
							my $nwwn = (Math::BigInt->new($hba->nodeWorldWideName))->as_hex();
							my $pwwn = (Math::BigInt->new($hba->portWorldWideName))->as_hex();
							$nwwn =~ s/^..//;
							$pwwn =~ s/^..//;
							$nwwn = join(':', unpack('A2' x 8, $nwwn));
							$pwwn = join(':', unpack('A2' x 8, $pwwn));

							if($demo eq "yes") {
								$nwwn = "XX:XX:XX:XX:XX:XX:XX:XX";
								$pwwn = "XX:XX:XX:XX:XX:XX:XX:XX";
								$fcfMac = "XX:XX:XX:XX:XX:XX";
								$vnportMac = "XX:XX:XX:XX:XX:XX";
							}
							$hbaString .= "<td>".$hbaType."</td><td>".$hba->device."</td><td>".$hba->pci."</td><td>".$hba->model."</td><td>".$hba->driver."</td><td>".$hba->status."</td><td><b>NWWN</b> ".$nwwn."</td><td><b>PWWN</b> ".$pwwn."</td>";
							if(($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') && $hbaType eq "FCoE") {
								$hbaString .= "<td><b><FCFMAC</b> ".$fcfMac."</td><td><b>VNPORTMAC</b> ".$vnportMac."</td>";
							}
							$hbaString .= "<td><b>PORT TYPE</b> ".$hba->portType->val."</td><td><b>SPEED</b> ".$hba->speed."</td></td>";
						} elsif($hba->isa("HostInternetScsiHba")) {
							$hbaString .= "<td>iSCSI</td><td>".$hba->device."</td><td>".$hba->pci."</td><td>".$hba->model."</td><td>".$hba->driver."</td><td>".$hba->status."</td><td>".(($hba->authenticationProperties->chapAuthEnabled) ? "CHAP ENABLED" : "CHAP DISABLED")."</td>";
						} elsif($hba->isa("HostParallelScsiHba")) {
							$hbaString .= "<td>SCSI</td><td>".$hba->device."</td><td>".$hba->pci."</td><td>".$hba->model."</td><td>".$hba->driver."</td><td>".$hba->status."</td>";
						} elsif($hba->isa("HostBlockHba")) {
							$hbaString .= "<td>BLOCK</td><td>".$hba->device."</td><td>".$hba->pci."</td><td>".$hba->model."</td><td>".$hba->driver."</td><td>".$hba->status."</td>";
						}
						$hbaString .= "</tr>\n";
					}
				}
			}
			######################
			# iSCSI
			######################
			if($HOST_ISCSI eq "yes" && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
				my $hbas;
				eval { $hbas = $local_host->config->storageDevice->hostBusAdapter; };
				if(!$@) {
					my @iSCSIHBAs = ();
					foreach my $hba (@$hbas) {
						if($hba->isa("HostInternetScsiHba")) {
							push @iSCSIHBAs, $hba->device;
						}
					}

					my $iscsiMgr;
					eval { $iscsiMgr = Vim::get_view(mo_ref => $local_host->configManager->iscsiManager); };
					if(!$@) {
						foreach my $iscsiHBA (@iSCSIHBAs) {
							my $iscsiPortInfo = $iscsiMgr->QueryBoundVnics(iScsiHbaName => $iscsiHBA);
							if(defined($iscsiPortInfo)) {
								foreach my $iscsiPort (@$iscsiPortInfo) {
									$iscsiString .= "<tr>";
									$iscsiString .= "<td>".$host_name."</td>";
									$iscsiString .= "<td>".(defined($iscsiPort->vnicDevice) ? $iscsiPort->vnicDevice : "N/A")."</td>";
									if($iscsiPort->vnic->spec->ip->ipAddress) {
										$iscsiString .= "<td>".$iscsiPort->vnic->spec->ip->ipAddress."</td>";
									} else { $iscsiString .= "<td>N/A</td>"; }
									if($iscsiPort->vnic->spec->ip->subnetMask) {
										$iscsiString .= "<td>".$iscsiPort->vnic->spec->ip->subnetMask."</td>";
									} else { $iscsiString .= "<td>N/A</td>"; }
									if($iscsiPort->vnic->spec->mac) {
										$iscsiString .= "<td>".$iscsiPort->vnic->spec->mac."</td>";
									} else { $iscsiString .= "<td>N/A</td>"; }
									if($iscsiPort->vnic->spec->mtu) {
										$iscsiString .= "<td>".$iscsiPort->vnic->spec->mtu."</td>";
									} else { $iscsiString .= "<td>N/A</td>"; }
									if(defined($iscsiPort->vnic->spec->tsoEnabled)) {
										$iscsiString .= "<td>".($iscsiPort->vnic->spec->tsoEnabled ? "YES" : "NO")."</td>";
									} else { $iscsiString .= "<td>N/A</td>"; }
									if($iscsiPort->pnic) {
										$iscsiString .= "<td>".$iscsiPort->pnic->linkSpeed->speedMb . " (" . ($iscsiPort->pnic->linkSpeed->duplex ? "FULL-DUPLEX" : "HALF-DUPLEX") . ")"."</td>";
									} else { $iscsiString .= "<td>N/A</td>"; }
									$iscsiString .= "<td>".(defined($iscsiPort->pnicDevice) ? $iscsiPort->pnicDevice : "N/A")."</td>";
									$iscsiString .= "<td>".(defined($iscsiPort->portgroupName) ? $iscsiPort->portgroupName : "N/A")."</td>";
									$iscsiString .= "<td>".(defined($iscsiPort->switchName) ? $iscsiPort->switchName : "N/A")."</td>";
									$iscsiString .= "<td>".(defined($iscsiPort->switchUuid) ? $iscsiPort->switchUuid : "N/A")."</td>";
									$iscsiString .= "<td>".(defined($iscsiPort->pathStatus) ? $iscsiPort->pathStatus : "N/A")."</td>";
									$iscsiString .= "</tr>";
								}
							}
						}
					}
				}
			}
			######################
			# CAPABILITY
			######################
			if($HOST_CAPABILITY eq "yes") {
				if($local_host->capability) {
					$capString .= "<tr>";
					$capString .= "<td>".$host_name."</td>";

					if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
						## MAX VMS ##
						if($local_host->capability->maxHostRunningVms) {
							$capString .= "<td>".$local_host->capability->maxHostRunningVms."</td>";
						} else { $capString .= "<td>N/A</td>"; }

						## MAX VCPU ##
						if($local_host->capability->maxHostSupportedVcpus) {
							$capString .= "<td>".$local_host->capability->maxHostSupportedVcpus."</td>";
						} else { $capString .= "<td>N/A</td>"; }

						## VMFS VERSION ##
						if($local_host->capability->supportedVmfsMajorVersion) {
							$capString .= "<td>".join(",",@{$local_host->capability->supportedVmfsMajorVersion})."</td>";
						} else { $capString .= "<td>N/A</td>"; }
					}

					## FT ##
					$capString .= "<td>".($local_host->capability->ftSupported ? "YES" : "NO")."</td>";

					## IPMI ##
					if($local_host->capability->ipmiSupported) {
						$capString .= "<td>".($local_host->capability->ipmiSupported ? "YES" : "NO")."</td>";
					} else {
						$capString .= "<td>N/A</td>";
					}

					## TPM ##
					$capString .= "<td>".($local_host->capability->tpmSupported ? "YES" : "NO")."</td>";

					## HV ##
					$capString .= "<td>".($local_host->capability->virtualExecUsageSupported ? "YES" : "NO")."</td>";

					if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
						if($hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
							## STORAGE IORM ##
							$capString .= "<td>".($local_host->capability->storageIORMSupported ? "YES" : "NO")."</td>";

							## DPG 2 ##
							$capString .= "<td>".($local_host->capability->vmDirectPathGen2Supported ? "YES" : "NO")."</td>";

							## vStorage ##
							$capString .= "<td>".($local_host->capability->vStorageCapable ? "YES" : "NO")."</td>";
						} else {
							$capString .= "<td>N/A</td>";
							$capString .= "<td>N/A</td>";
							$capString .= "<td>N/A</td>";
						}
					}

					## SSL THUMBPRINT ##
					if($local_host->capability->loginBySSLThumbprintSupported) {
						$capString .= "<td>".($local_host->capability->loginBySSLThumbprintSupported ? "YES" : "NO")."</td>";
					} else {
						$capString .= "<td>N/A</td>";
					}

					$capString .= "</tr>\n";
				}
			}
			######################
			# CONFIGURATIONS
			######################
			if($HOST_CONFIGURATION eq "yes") {
				my $netMgr = Vim::get_view(mo_ref => $local_host->configManager->networkSystem);

				$configString .= "\n<table border=\"1\">\n<tr><th colspan=3>".$host_name."</th></tr>\n";

				#############
				## VMOTION ##
				#############
				if($HOST_VMOTION eq "yes") {
					if($local_host->summary->config->vmotionEnabled) {
						$configString .= "<tr><th>VMOTION ENABLED </th><td>YES</td></tr>\n";
						if($demo eq "no") {
							$configString .= "<tr><th>IP ADDRESS </th><td>".$local_host->config->vmotion->ipConfig->ipAddress." => ".$local_host->summary->config->name."</td></tr>\n";
							$configString .= "<tr><th>NETMASK </th><td>".$local_host->config->vmotion->ipConfig->subnetMask."</td></tr>\n";
						} else {
							$configString .= "<tr><th>IP ADDRESS </th><td>X.X.X.X</td></tr>\n";
							$configString .= "<tr><th>NETMASK </th><td>X.X.X.X</td></tr>\n";
						}
					}
				}

				#############
				## GATEWAY ##
				#############
				if($HOST_GATEWAY eq "yes") {
					if($demo eq "no") {
						if($netMgr->consoleIpRouteConfig) {
							if($netMgr->consoleIpRouteConfig->defaultGateway) {
								$configString .= "<tr><th>GATEWAY </th><td>".$netMgr->consoleIpRouteConfig->defaultGateway."</td></tr>\n";
							} else {
								$configString .= "<tr><th>GATEWAY </th><td>0.0.0.0</td></tr>\n";
							}
							if($netMgr->consoleIpRouteConfig->ipV6DefaultGateway) {
								$configString .= "<tr><th>IPv6 GATEWAY </th><td>".$netMgr->consoleIpRouteConfig->ipV6DefaultGateway."</td></tr>\n";
							} else {
								$configString .= "<tr><th>IPv6 GATEWAY </th><td>0.0.0.0</td></tr>\n";
							}
						} else {
							$configString .= "<tr><th>GATEWAY </th><td>N/A</td></tr>\n";
							$configString .= "<tr><th>IPv6 GATEWAY </th><td>N/A</td></tr>\n";
						}
						if($netMgr->ipRouteConfig->defaultGateway) {
							$configString .= "<tr><th>VMKERNEL GATEWAY </th><td>".$netMgr->ipRouteConfig->defaultGateway."</td></tr>\n";
						} else {
						$configString .= "<tr><th>VMKERNEL GATEWAY </th><td>0.0.0.0</td></tr>\n";
						}
						if($netMgr->ipRouteConfig->ipV6DefaultGateway) {
							$configString .= "<tr><th>VMKERNEL IPv6 GATEWAY </th><td>".$netMgr->ipRouteConfig->ipV6DefaultGateway."</td></tr>\n";
						} else {
							$configString .= "<tr><th>VMKERNEL IPv6 GATEWAY </th><td>0.0.0.0</td></tr>\n";
						}
					} else {
						$configString .= "<tr><th>GATEWAY </th><td>X.X.X.X</td></tr>\n";
					}
				}

				#####################
				## SOFTWARE iSCSI  ##
				#####################
				if($HOST_ISCSI eq "yes") {
					$configString .= "<tr><th>SOFTWAE iSCSI ENABLED</th><td>".($local_host->config->storageDevice->softwareInternetScsiEnabled ? "YES" : "NO")."</td></tr>\n";
				}

				#############
				## IPV6    ##
				#############
				if($HOST_IPV6 eq "yes") {
					$configString .= "<tr><th>IPv6 ENABLED</th><td>".($local_host->config->network->ipV6Enabled ? "YES" : "NO")."</td></tr>\n";
				}

				#############
				# FT       ##
				#############
				if($HOST_FT eq "yes") {
					$configString .= "<tr><th>FT ENABLED</th><td>".($local_host->summary->config->faultToleranceEnabled ? "YES" : "NO")."</td></tr>\n";
				}

				#############
				# SSL      ##
				#############
				if($HOST_SSL eq "yes") {
					$configString .= "<tr><th>SSL THUMBPRINT</th><td>".($local_host->summary->config->sslThumbprint ? $local_host->summary->config->sslThumbprint : "N/A")."</td></tr>\n";
				}


				#############
				## DNS     ##
				#############
				if($HOST_DNS eq "yes") {
					my $searchDomains = $local_host->config->network->dnsConfig->searchDomain;
					my $searchString = "";
					foreach(@$searchDomains) {
						$searchString .= "search ".$_."<br/>";
					}
					my $dnsAddress = $local_host->config->network->dnsConfig->address;
					my $dnsString = "";
					foreach(@$dnsAddress) {
						$dnsString .= "nameserver ".$_."<br/>";
					}
					if($demo eq "no") {
						$configString .= "<tr><th>DNS</th><td>"."domain ".($local_host->config->network->dnsConfig->domainName ? $local_host->config->network->dnsConfig->domainName : "N/A")."<br/>".$searchString.$dnsString."</td></tr>\n";
					} else {
						$configString .= "<tr><th>DNS</th><td>domain demo_mode<br/>search demo_mode<br/>nameserver demo_mode</td></tr>\n";
					}
				}

				#############
				## UPTIME  ##
				#############
				if($HOST_UPTIME eq "yes") {
					my ($host_date,$host_time) = split('T',$local_host->runtime->bootTime);
					my $todays_date = giveMeDate('YMD');
					chomp($todays_date);
					$configString .= "<tr><th>UPTIME</th><td>".&days_between($host_date, $todays_date)." Days - ".$local_host->runtime->bootTime."</td></tr>\n";
				}

				#################
				## DIAGONISTIC ##
				#################
				if($HOST_DIAGONISTIC eq "yes") {
					if($local_host->config->activeDiagnosticPartition) {
						my $diag_string .= "<tr><td>".$local_host->config->activeDiagnosticPartition->diagnosticType."</td><td>".$local_host->config->activeDiagnosticPartition->id->diskName.$local_host->config->activeDiagnosticPartition->id->partition."</td><td>".$local_host->config->activeDiagnosticPartition->storageType."</td></tr>";
						$configString .= "<tr><th>DIAGNOSTIC PARTITION</th><td><table border=\"1\" width=100%><tr><th>TYPE</th><th>PARITION</th><th>STORAGE TYPE</th></tr>".$diag_string."</table></td></tr>\n";
					}
				}

				###################
				## AUTH SERVICES ##
				###################
				if($HOST_AUTH_SERVICE eq "yes" && $hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
					my $authMgr = Vim::get_view(mo_ref => $local_host->configManager->authenticationManager);
					if($authMgr->info) {
						my $authConfigs = $authMgr->info->authConfig;
						my $authString = "";
						foreach(@$authConfigs) {
							my ($authType,$authEnabled,$authStatus,$authDomain,$trustedDomains) = ("","","","","");

							if($_->isa('HostLocalAuthenticationInfo')) {
								$authType = "LOCAL";
								$authEnabled = ($_->enabled ? "YES" : "NO");
								$authStatus = "N/A";
								$authDomain = "N/A";
								$trustedDomains = "N/A";
							}
							elsif($_->isa('HostActiveDirectoryInfo')) {
								$authType = "ACTIVE DIRECTORY";
								$authEnabled = ($_->enabled ? "YES" : "NO");
								$authStatus = ($_->domainMembershipStatus ? $_->domainMembershipStatus : "N/A");
								$authDomain = ($_->joinedDomain ? $_->joinedDomain : "N/A");

								if($_->trustedDomain) {
									my $domains = $_->trustedDomain;
									foreach(@$domains) {
										$trustedDomains .= $_ . "<br/>";
									}
								} else {
									$trustedDomains = "N/A";
								}
							}
							$authString .= "<tr><td>".$authType."</td><td>".$authEnabled."</td><td>".$authStatus."</td><td>".$authDomain."</td><td>".$trustedDomains."</td></tr>";

						}
						$configString .= "<tr><th>AUTHENTICATION SERVICE(s)</th><td><table border=\"1\" width=100%><tr><th>AUTH TYPE</th><th>ENABLED</th><th>STATUS</th><th>DOMAIN</th><th>TRUSTED DOMAIN</th></tr>".$authString."</table></td></tr>\n";
					}
				}

				###############
				## SERVICES  ##
				###############
				if($HOST_SERVICE eq "yes") {
					my $services = $local_host->config->service->service;
					if($services) {
						my $serviceString = "";
						foreach(@$services) {
							$serviceString .= "<tr><td>".$_->label."</td>";
							if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
								if($_->sourcePackage) {
									$serviceString .= "<td>".$_->sourcePackage->sourcePackageName."</td>";
								} else { $serviceString .= "<td>N/A</td>"; }
							}
							$serviceString .= "<td>".$_->policy."</td><td>".(($_->running) ? "YES" : "NO")."</td></tr>";
						}
						if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
							$configString .= "<tr><th>SERVICE(s)</th><td><table border=\"1\" width=100%><tr><th>NAME</th><th>SOURCE PACKAGE</ah><th>POLICY TYPE</th><th>RUNNING</th></tr>".$serviceString."</table></td></tr>\n";
						} else {
							$configString .= "<tr><th>SERVICE(s)</th><td><table border=\"1\" width=100%><tr><th>NAME</th><th>POLICY TYPE</th><th>RUNNING</th></tr>".$serviceString."</table></td></tr>\n";
						}
					}
				}

				#############
				## NTP     ##
				#############
				if($HOST_NTP eq "yes") {
					if($local_host->config->dateTimeInfo) {
						my $ntps;
						eval { $ntps = $local_host->config->dateTimeInfo->ntpConfig->server; };
						if(!$@) {
							my $ntpString = "";
							if($ntps) {
								foreach (@$ntps) {
									$ntpString .= "$_<br/>";
								}
							} else { $ntpString = "NONE CONFIGURED"; }
							$ntpString = "<tr><td>".$ntpString."</td>";
							$ntpString .= "<td>".$local_host->config->dateTimeInfo->timeZone->description."</td><td>".$local_host->config->dateTimeInfo->timeZone->gmtOffset."</td><td>".$local_host->config->dateTimeInfo->timeZone->name."</td></tr>";
							$configString .= "<tr><th>NTP</th><td><table border=\"1\" width=100%><tr><th>NTP SERVERS</th><th>TIME ZONE</th><th>GMT OFFSET</th><th>LOCATION</th></tr>".$ntpString."</table></td></tr>\n";
						}
					}
				}

				###########
				## VSWIF ##
				###########
				if($HOST_VSWIF eq "yes") {
					if($local_host->config->network->consoleVnic) {
						my $vswifString = "";
						my $console_vnics = $local_host->config->network->consoleVnic;
						foreach(@$console_vnics) {
							if($demo eq "no") {
								$vswifString .= "<tr><td>".$_->device."</td><td>".$_->portgroup."</td><td>".$_->spec->ip->ipAddress."</td><td>".$_->spec->ip->subnetMask."</td><td>".$_->spec->mac."</td><td>".(($_->spec->ip->dhcp) ? "YES" : "NO")."</td></tr>";
							} else {
								$vswifString .= "<tr><td>".$_->device."</td><td>demo_mode</td><td>X.X.X.X</td><td>X.X.X.X</td><td>demo_mode</td><td>".(($_->spec->ip->dhcp) ? "YES" : "NO")."</td></tr>";
							}
						}
						$configString .= "<tr><th>VSWIF(s)</th><td><table border=\"1\" width=100%><tr><th>NAME</th><th>PORTGROUP</th><th>IP ADDRESS</th><th>NETMASK</th><th>MAC</th><th>DHCP</th></tr>".$vswifString."</table></td></tr>\n";
					}
				}

				##############
				## VMKERNEL ##
				##############
				if($HOST_VMKERNEL eq "yes") {
					if($local_host->config->network->vnic) {
						my $vmkString = "";
						my $vmks = $local_host->config->network->vnic;
						foreach(@$vmks) {
							if($demo eq "no") {
								$vmkString .= "<tr><td>".$_->device."</td><td>".$_->portgroup."</td><td>".$_->spec->ip->ipAddress."</td><td>".$_->spec->ip->subnetMask."</td><td>".$_->spec->mac."</td><td>".(($_->spec->ip->dhcp) ? "YES" : "NO")."</td></tr>";
							} else {
								$vmkString .= "<tr><td>".$_->device."</td><td>demo_mode</td><td>X.X.X.X</td><td>X.X.X.X</td><td>X.X.X.X</td><td>".(($_->spec->ip->dhcp) ? "YES" : "NO")."</td></tr>";
							}
						}
						$configString .= "<tr><th>VMKERNEL(s)</th><td><table border=\"1\" width=100%><tr><th>INTERFACE</th><th>PORTGROUP</th><th>IP ADDRESS</th><th>NETMASK</th><th>MAC</th><th>DHCP</th></tr>".$vmkString."</table></td></tr>\n";
					}
				}

				#############
				## VSWITCH ##
				#############
				if($HOST_VSWITCH eq "yes") {
					my %vmmac_to_portgroup_mapping = ();
					my %cdp_enabled = ();
					my $vswitches = $local_host->config->network->vswitch;

					my $vswitchString = "";
					foreach my $vSwitch(@$vswitches) {
						my ($pNicName,$mtu,$cdp_vswitch,$pNicKey) = ("","","","");
						my $vswitch_name = $vSwitch->name;
						my $pNics = $vSwitch->pnic;

						foreach (@$pNics) {
							$pNicKey = $_;
							if ($pNicKey ne "") {
								$pNics = $netMgr->networkInfo->pnic;
								foreach my $pNic (@$pNics) {
									if ($pNic->key eq $pNicKey) {
										$pNicName = $pNicName ? ("$pNicName," . $pNic->device) : $pNic->device;
										if($cdp_enabled{$pNic->device}) {
											$cdp_vswitch = $cdp_enabled{$pNic->device};
										} else {
											$cdp_vswitch = "N/A";
										}
									}
								}
							}
						}
						$mtu = $vSwitch->{mtu} if defined($vSwitch->{mtu});
						$vswitchString .= "<tr><th>VSWITCH NAME</th><th>NUM OF PORTS</th><th>USED PORTS</th><th>MTU</th><th>UPLINKS</th><th>CDP ENABLED</th></tr><tr><td>".$vSwitch->name."</td><td>".$vSwitch->numPorts."</td><td>".($vSwitch->numPorts - $vSwitch->numPortsAvailable)."</td><td>".$mtu."</td><td>".$pNicName."</td><td>".$cdp_vswitch."</td></tr>\n";
						$vswitchString .= "<tr><th>PORTGROUP NAME</th><th>VLAN ID</th><th>USED PORTS</th><th colspan=3>UPLINKS</th></tr>\n";
						my $portGroups = $vSwitch->portgroup;
						foreach my $portgroup(@$portGroups) {
							my $pg = FindPortGroupbyKey ($netMgr, $vSwitch->key, $portgroup);
							next unless (defined $pg);
							my $usedPorts = (defined $pg->port) ? $#{$pg->port} + 1 : 0;
							if($demo eq "no") {
								$vswitchString .= "<tr><td>".$pg->spec->name."</td><td>".$pg->spec->vlanId."</td><td>".$usedPorts."</td><td colspan=3>".$pNicName."</td></tr>\n";
							} else {
								$vswitchString .= "<tr><td>demo_mode</td><td>demo_mode</td><td>".$usedPorts."</td><td colspan=3>".$pNicName."</td></tr>\n";
							}
							$vswitch_portgroup_mappping{$pg->spec->name} = $vswitch_name;
						}
					}
					$configString .= "<tr><th>VSWITCH(s)</th><td><table border=\"1\">".$vswitchString."</table></td></tr>\n";

					my $networks = Vim::get_views(mo_ref_array => $local_host->network);
					foreach my $portgroup(@$networks) {
						my $vms_device = Vim::get_views(mo_ref_array => $portgroup->vm, properties => ["config.name","config.hardware.device"]);
						foreach(@$vms_device) {
							my $vmname = $_->{'config.name'};
							my $devices = $_->{'config.hardware.device'};

							foreach(@$devices) {
								if($_->isa("VirtualEthernetCard")) {
									$vmmac_to_portgroup_mapping{$vmname} = $portgroup->name;
								}
							}
						}
					}
				}

				##########
				## SNMP ##
				##########
				if($HOST_SNMP eq "yes") {
					my $snmp_system;
					eval { $snmp_system = Vim::get_view (mo_ref => $local_host->configManager->snmpSystem); };
					if(!$@) {
						if(defined($snmp_system->configuration)) {
							if($snmp_system->configuration->enabled) {
								my $snmpString = "";
								$snmpString .= "<tr><td>".$snmp_system->configuration->port."</td><td>";
								my $ro_community = $snmp_system->configuration->readOnlyCommunities;
								foreach(@$ro_community) {
									$snmpString .= $_ . ", ";
								}
								$snmpString .= "</td><td>";
								my $trap_targets = $snmp_system->configuration->trapTargets;
								foreach(@$trap_targets) {
									$snmpString .= "<b>Community:</b> " . $_->community . " <b>Hostname:</b> " . $_->hostName . " <b>Port:</b> " . $_->port . "<br/>\n";
								}
								$snmpString .= "</td></tr>";
								$configString .= "<tr><th>SNMP</th><td><table border=\"1\" width=100%><tr><th>SNMP PORT</th><th>RO COMMUNITIES</th><th>TRAP TARGETS</th></tr>".$snmpString."</table></td></tr>\n";
							}
						}
					}
				}

				##############
				## FIREWALL ##
				##############
				if($HOST_FIREWALL eq "yes") {
					if($local_host->config->firewall) {
						my $fw_sys = $local_host->config->firewall;
						my $fw_rules = $fw_sys->ruleset;
						my $fw_known_string = "";
						my $fw_rule_string = "";
						foreach my $rule ( sort{$a->label cmp $b->label}@$fw_rules) {
							if($rule->enabled) {
								my ($allowedIPs) = ("");
								if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
									if(defined($rule->allowedHosts)) {
										if($rule->allowedHosts->allIp) {
											$allowedIPs = "all";
										} else {
											my $ipNetworks = $rule->allowedHosts->ipNetwork;
											foreach(@$ipNetworks) {
												$allowedIPs .= $_->network . "/" . $_->prefixLength . ", ";
											}
										}
									}
								}
								my $firewallRules = $rule->rule;
								my ($fwDirection,$fwPort,$fwPortType,$fwProto) = ("N/A","N/A","N/A","N/A");
								foreach(@$firewallRules) {
									$fwDirection = $_->direction->val;
									$fwPort = $_->port;
									if($_->endPort) {
										$fwPort .= "-" . $_->endPort;
									}
									if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
										$fwPortType = $_->portType ? uc($_->portType->val) : "N/A";
									}
									$fwProto = $_->protocol;
									$fw_known_string .= "<tr><td>".$rule->label."</td><td>".$fwDirection."</td><td>".$fwPortType."</td><td>".$fwPort."</td><td>".$fwProto."</td><td>".$allowedIPs."</td></tr>\n";
								}
							}
						}
						$configString .= "<tr><th>FIREWALL<br/> KNOWN SERVICES ENABLED</th><td><table border=\"1\" width=100%><tr><th>LABEL</th><th>DIRECTION</th><th>PORT TYPE</th><th>PORT</th><th>PROTOCOL</th><th>ALLOWED IPS</th>".$fw_known_string."</table></td></tr>\n";

						my $defaultPolicy = "<tr><td>".($fw_sys->defaultPolicy->incomingBlocked ? "YES" : "NO")."</td><td>".($fw_sys->defaultPolicy->outgoingBlocked ? "YES" : "NO")."</td></tr>\n";
						$configString .= "<tr><th>FIREWALL POLICY</th><td><table border=\"1\" width=100%><tr><th>INCOMING ENABLED</th><th>OUTGOING ENABLED</th></tr>".$defaultPolicy."</table></td></tr>\n";
					}
				}

				###########
				## POWER ##
				###########
				if($HOST_POWER eq "yes") {
					if($local_host->hardware->cpuPowerManagementInfo) {
						my $cpu_power_info = "";
						$cpu_power_info .= "<tr><td>".($local_host->hardware->cpuPowerManagementInfo->currentPolicy)."</td><td>".($local_host->hardware->cpuPowerManagementInfo->hardwareSupport)."</td></tr>";
						$configString .= "<tr><th>CPU POWER MGMT INFO</th><td><table border=\"1\" width=100%><tr><th>CURRENT POLICY</th><th>HARDWARE SUPPORT</th></tr>".$cpu_power_info."</table></td></tr>\n";
					}
				}

				######################
				# FEATURE VERSION
				######################
				if($HOST_FEATURE_VERSION eq "yes" && $hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
					if($local_host->summary->config->featureVersion) {
						my $featurever = $local_host->summary->config->featureVersion;
						my $featureString = "";
						foreach(@$featurever) {
							$featureString .= "<tr><td>".$_->key."</td><td>".$_->value."</td></tr>\n";
						}
						$configString .= "<tr><th>FEATURE VERSION</th><td><table border=\"1\" width=100%><tr><th>FEATURE</th><th>VERSION</th></tr>".$featureString."</table></td></tr>\n";
					}
				}

				$configString .= "</table>\n";
			}
			######################
			# ADVANCED OPTIONS
			######################
			if($HOST_ADVOPT eq "yes") {
				my $advopts = Vim::get_view(mo_ref => $local_host->configManager->advancedOption);
				my $advSettings = $advopts->setting;

				my ($diskUDR,$diskULR,$diskSNRO,$scsiCR,$nfsMV,$SBS,$RBS,$netTHS,$nfsHF,$nfsHT,$nfsHMF,$vmkernelBSM,$vmfs3HAL,$dataMHAM,$dataMHAI) = ("N/A","N/A","N/A","N/A","N/A","N/A","N/A","N/A","N/A","N/A","N/A","N/A","N/A","N/A","N/A");

				foreach(@$advSettings) {
					my $key = $_->key;
					my $value = $_->value;

					if($key eq "Disk.UseDeviceReset") { $diskUDR = $value; }
					if($key eq "Disk.UseLunReset") { $diskULR = $value; }
					if($key eq "Disk.SchedNumReqOutstanding") { $diskSNRO = $value; }
					if($key eq "Scsi.ConflictRetries") { $scsiCR = $value; }
					if($key eq "NFS.MaxVolumes") { $nfsMV = $value; }
					if($key eq "SendBufferSize") { $SBS = $value; }
					if($key eq "ReceiveBufferSize") { $RBS = $value; }
					if($key eq "Net.TcpipHeapSize") { $netTHS = $value; }
					if($key eq "NFS.HeartbeatFrequency") { $nfsHF = $value; }
					if($key eq "NFS.HeartbeatTimeout") { $nfsHT = $value; }
					if($key eq "NFS.HeartbeatMaxFailures") { $nfsHMF = $value; }
					if($key eq "VMkernel.Boot.techSupportMode") { $vmkernelBSM = $value; }
					if($key eq "VMFS3.HardwareAcceleratedLocking") { $vmfs3HAL = $value; }
					if($key eq "DataMover.HardwareAcceleratedMove") { $dataMHAM = $value; }
					if($key eq "DataMover.HardwareAcceleratedInit") { $dataMHAI = $value; }
				}
				$advString .= "<tr>";
				$advString .= "<td>".$host_name."</td>";
				$advString .= "<td>".$diskUDR."</td>";
				$advString .= "<td>".$diskULR."</td>";
				$advString .= "<td>".$diskSNRO."</td>";
				$advString .= "<td>".$scsiCR."</td>";
				$advString .= "<td>".$nfsMV."</td>";
				$advString .= "<td>".$SBS."</td>";
				$advString .= "<td>".$RBS."</td>";
				$advString .= "<td>".$netTHS."</td>";
				$advString .= "<td>".$nfsHF."</td>";
				$advString .= "<td>".$nfsHT."</td>";
				$advString .= "<td>".$nfsHMF."</td>";
				$advString .= "<td>".$vmkernelBSM."</td>";
				$advString .= "<td>".$vmfs3HAL."</td>";
				$advString .= "<td>".$dataMHAM."</td>";
				$advString .= "<td>".$dataMHAI."</td>";
				$advString .= "</tr>\n";
			}
			######################
			# HOST AGENT SETTING
			######################
			if($HOST_AGENT eq "yes" && $atype eq "VirtualCenter" && $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
				if(defined($local_host->configManager->esxAgentHostManager)) {
					my $hostAgentMgr = Vim::get_view(mo_ref => $local_host->configManager->esxAgentHostManager);
					my ($agentDSName,$agentNetName) = ("N/A","N/A");

					if($hostAgentMgr->configInfo->agentVmDatastore) {
						my $agentDSNameTmp = Vim::get_view(mo_ref => $hostAgentMgr->configInfo->agentVmDatastore, properties => ['name']);
						$agentDSName = $agentDSNameTmp->{'name'};
					}
					if($hostAgentMgr->configInfo->agentVmNetwork) {
						my $agentNetNameTmp = Vim::get_view(mo_ref => $hostAgentMgr->configInfo->agentVmNetwork, properties => ['name']);
						$agentNetName = $agentNetNameTmp->{'name'};
					}

					if($agentDSName ne "N/A" && $agentNetName ne "N/A") {
						$agentString .= "<tr>";
						$agentString .= "<td>".$host_name."</td>";
						$agentString .= "<td>".$agentDSName."</td>";
						$agentString .= "<td>".$agentNetName."</td>";
						$agentString .= "</tr>\n";
					}
				}
			}
			######################
			# NUMA
			######################
			if($HOST_NUMA eq "yes") {
				if($local_host->hardware->numaInfo) {
					my $numaInfo = $local_host->hardware->numaInfo;
					if($numaInfo->numNodes == 0) {
						$numaString .= "<tr><td>".$host_name."</td><td>NUMA-incapable</td><td>".$numaInfo->type."</td><td>N/A</td>";
					} else {
						$numaString .= "<tr><td>".$host_name."</td><td>".$numaInfo->numNodes."</td><td>".$numaInfo->type."</td><td>";
						if($numaInfo->numaNode) {
							my $nodes = $numaInfo->numaNode;
							$numaString .= "<table border=\"1\"><tr><th>NODE ID</th><th>CPU ID</th><th>MEM RANGE BEGIN</th><th>MEM RANGE LENGTH</th></tr>";
							foreach(@$nodes) {
								my $cpuID = $_->cpuID;
								my $idString = "";
								foreach(@$cpuID) {
									$idString = $_ . " " . $idString;
								}
								$numaString .= "<tr><td>".$_->typeId."</td><td>&nbsp;[".$idString."]&nbsp;</td><td>".&prettyPrintData($_->memoryRangeBegin,'B')."</td><td>".&prettyPrintData($_->memoryRangeLength,'B')."</td></tr>";
							}
							$numaString .= "</table>";
						} else {
							$numaString .= "N/A</td>"
						}
						$numaString .= "<tr>\n";
					}
				}
			}
			######################
			# CDP
			######################
			if($HOST_CDP eq "yes") {
				my $netMgr = Vim::get_view(mo_ref => $local_host->configManager->networkSystem);
				my ($device,$port,$address,$cdp_ver,$devid,$duplex,$platform,$prefix,$location,$mgmt_addr,$cdpMtu,$samples,$sys_ver,$sys_name,$sys_oid,$timeout,$ttl,$vlan);
				my @physicalNicHintInfo = $netMgr->QueryNetworkHint();
				foreach (@physicalNicHintInfo){
					foreach ( @{$_} ){
						if($_->connectedSwitchPort) {
							if($demo eq "no") {
								$device = $_->device;
								$port = $_->connectedSwitchPort->portId;
								$address = ($_->connectedSwitchPort->address ? $_->connectedSwitchPort->address : "N/A");
								$cdp_ver = ($_->connectedSwitchPort->cdpVersion ? $_->connectedSwitchPort->cdpVersion : "N/A");
								$devid = ($_->connectedSwitchPort->devId ? $_->connectedSwitchPort->devId : "N/A");
								$duplex = ($_->connectedSwitchPort->fullDuplex ? ($_->connectedSwitchPort->fullDuplex ? "YES" : "NO") : "N/A");
								$platform = ($_->connectedSwitchPort->hardwarePlatform ? $_->connectedSwitchPort->hardwarePlatform : "N/A");
								$prefix = ($_->connectedSwitchPort->ipPrefix ? $_->connectedSwitchPort->ipPrefix : "N/A");
								$location = ($_->connectedSwitchPort->location ? $_->connectedSwitchPort->location : "N/A");
								$mgmt_addr = ($_->connectedSwitchPort->mgmtAddr ? $_->connectedSwitchPort->mgmtAddr : "N/A");
								$cdpMtu = ($_->connectedSwitchPort->mtu ? $_->connectedSwitchPort->mtu : "N/A");
								$samples = ($_->connectedSwitchPort->samples ? $_->connectedSwitchPort->samples : "N/A");
								$sys_ver = ($_->connectedSwitchPort->softwareVersion ? $_->connectedSwitchPort->softwareVersion : "N/A");
								$sys_name = ($_->connectedSwitchPort->systemName ? $_->connectedSwitchPort->systemName : "N/A");
								$sys_oid = ($_->connectedSwitchPort->systemOID ? $_->connectedSwitchPort->systemOID : "N/A");
								$timeout = ($_->connectedSwitchPort->timeout ? $_->connectedSwitchPort->timeout : "N/A");
								$ttl = ($_->connectedSwitchPort->ttl ? $_->connectedSwitchPort->ttl : "N/A");
								$vlan = ($_->connectedSwitchPort->vlan ? $_->connectedSwitchPort->vlan : "N/A");
							} else {
								($device,$address,$cdp_ver,$devid,$duplex,$platform,$prefix,$location,$mgmt_addr,$cdpMtu,$samples,$sys_ver,$sys_name,$sys_oid,$timeout,$ttl,$vlan) = ("demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode","demo_mode");
							}
							$cdpString .= "<tr><td>".$host_name."</td><td>".$device."</td><td>".$mgmt_addr."</td><td>".$address."</td><td>".$prefix."</td><td>".$location."</td><td>".$sys_name."</td><td>".$sys_ver."</td><td>".$sys_oid."</td><td>".$platform."</td><td>".$devid."</td><td>".$cdp_ver."</td><td>".$duplex."</td><td>".$cdpMtu."</td><td>".$timeout."</td><td>".$ttl."</td><td>".$vlan."</td><td>".$samples."</td></tr>\n";
						}
					}
				}
			}
			######################
			# DVS
			######################
			if($HOST_DVS eq "yes") {
				if($atype eq 'VirtualCenter') {
					my ($dvsMgr,$dvs,$dvpg,$dvs_string);
					eval { $dvsMgr = Vim::get_view(mo_ref => $sc->dvSwitchManager); };
					if(!$@) {
						my $dvs_target = $dvsMgr->QueryDvsConfigTarget(host => $local_host);
						if($dvs_target) {
							$dvs = $dvs_target->distributedVirtualSwitch;
							$dvpg = $dvs_target->distributedVirtualPortgroup;
						}
						if($dvpg) {
							foreach(@$dvpg) {
								$vswitch_portgroup_mappping{$_->portgroupName} = $_->switchName;
							}
						}
						if($dvs) {
							foreach(@$dvs) {
								my $sName = defined $_->switchName ? $_->switchName : "N/A";
								if(!$seen_dvs{$sName}) {
									my $sUuid = ($_->switchUuid ? $_->switchUuid : "N/A");
									my $dv_switch = Vim::get_view(mo_ref => $_->distributedVirtualSwitch);
									my $desc = ($dv_switch->summary->description ? $dv_switch->summary->description : "N/A");
									my $contact_name = ($dv_switch->summary->contact->name ? $dv_switch->summary->contact->name : "N/A");
									my $contact_con = ($dv_switch->summary->contact->contact ? $dv_switch->summary->contact->contact : "");
									my $contact_info = $contact_name . " " . $contact_con;
									my $build = ($dv_switch->summary->productInfo->build ? $dv_switch->summary->productInfo->build : "N/A");
									my $bid = ($dv_switch->summary->productInfo->bundleId ? $dv_switch->summary->productInfo->bundleId : "N/A");
									my $burl = ($dv_switch->summary->productInfo->bundleUrl ? $dv_switch->summary->productInfo->bundleUrl: "N/A");
									my $fclass = ($dv_switch->summary->productInfo->forwardingClass ? $dv_switch->summary->productInfo->forwardingClass : "N/A");
									my $vendor = ($dv_switch->summary->productInfo->vendor ? $dv_switch->summary->productInfo->vendor : "N/A");
									my $version = ($dv_switch->summary->productInfo->version ? $dv_switch->summary->productInfo->version : "N/A");
									my $ports = ($dv_switch->summary->numPorts ? $dv_switch->summary->numPorts : "N/A");
									$dvs_string = "<tr><td>".$sName."</td><td>".$desc."</td><td>".$contact_info."</td><td>".$vendor."</td><td>".$version."</td><td>".$sUuid."</td><td>".$build."</td><td>".$bid."</td><td>".$build."</td><td>".$burl."</td><td>".$fclass."</td><td>".$ports."</td></tr>\n";
									push @dvs, $dvs_string;
								}
								$seen_dvs{$sName} = 1;
							}
						}
					}
				}
			}
			######################
			# LUN
			######################
			if($HOST_LUN eq "yes") {
				my $ss = Vim::get_view(mo_ref => $local_host->configManager->storageSystem);
				my $fsmount = $ss->fileSystemVolumeInfo->mountInfo;
				my $luns = $ss->storageDeviceInfo->scsiLun;
				my ($volume,$extents,$diskName,$partition,$deviceName,$lunname,$volumename,$vendor,$model,$queuedepth,$vStorageSupport,$states) = ('','','','','','','','','','','','');

				foreach my $fsm (@$fsmount) {
					$volume = $fsm->volume;
					if ($volume->type eq 'VMFS') {
						$extents = $volume->extent;
						my $i = 0;
						foreach my $extent (@$extents) {
							$diskName = $extent->diskName;
							my $lun_row = "";
							foreach my $lun (sort {$a->canonicalName cmp $b->canonicalName} @$luns) {
								if ($diskName eq $lun->canonicalName) {
									$deviceName = $lun->deviceName;
									$volumename = $volume->name;
									$lunname = $lun->canonicalName;
									$vendor = $lun->vendor;
									$model = $lun->model;
									$queuedepth = $lun->queueDepth;
									if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
										if($hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
											$vStorageSupport = ($lun->vStorageSupport ? $lun->vStorageSupport : "N/A");
										} else {
											$vStorageSupport = "N/A"
										}
									}
									$states = $lun->operationalState;
									last;
								}
							}
							$partition = $extent->partition;
							$luns{$volume->uuid} .= $host_name . "_" . $lunname . ",";
							$lun_row .= "<td>".$volumename."</td>";
							$lun_row .= "<td>"."$diskName:$partition"."</td>";
							$lun_row .= "<td>"."$deviceName:$partition"."</td>";
							if($queuedepth) { $lun_row .= "<td>".$queuedepth."</td"; } else { $lun_row .= "<td>N/A</td>"; }
							my $state_string = "";
							foreach (@$states) {
								$state_string .= $_." ";
							}
							if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
								if($hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
									$lun_row .= "<td>".$vStorageSupport."</td>";
								} else {
									$lun_row .= "<td>N/A</td>";
								}
							}
							$lun_row .= "<td>".$state_string."</td><td>".$vendor."</td><td>".$model."</td>";
							$lun_row_info{$volume->uuid} = $lun_row;
						}
					}
				}
			}
			######################
			# DATASTORE
			######################
			if($HOST_DATASTORE eq "yes") {
				my $ds_views = Vim::get_views (mo_ref_array => $local_host->datastore);
				my $ctr = 0;
				foreach my $ds (sort {$a->info->name cmp $b->info->name} @$ds_views) {
					my $ds_row = "";
					if($ds->summary->accessible) {
						#capture unique datastores seen in cluster
						if (!grep {$_ eq $ds->info->name} @datastores_seen) {
							push @datastores_seen,$ds->info->name;
							my ($perc_free,$perc_string,$ds_used,$ds_free,$ds_cap,$ds_block,$ds_ver) = ("","","","","","N/A","N/A");
							if ( ($ds->summary->freeSpace gt 0) || ($ds->summary->capacity gt 0) ) {
								$ds_cap = &restrict_num_decimal_digits($ds->summary->capacity/1024/1000,2);
								$ds_used = prettyPrintData(($ds->summary->capacity - $ds->summary->freeSpace),'B');
								$ds_free = &restrict_num_decimal_digits(($ds->summary->freeSpace/1024/1000),2);
								$perc_free = &restrict_num_decimal_digits(( 100 * $ds_free / $ds_cap),2);
								$perc_string = getColor($perc_free);
								if($ds->summary->type eq 'VMFS') {
									$ds_block = $ds->info->vmfs->blockSizeMb;
									$ds_ver = $ds->info->vmfs->version;
								}
							} else {
								($perc_free,$ds_used,$ds_free) = ("UNKNOWN","UNKNOWN","UNKNOWN");
							}

							my $vmsInDS = Vim::get_views(mo_ref_array => $ds->vm,properties => ['name']);

							if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
								my ($iormEnable,$iormThres,$dsMaintMode,$iormAggDisable,$iormStatsCollEnable) = ("N/A","N/A","N/A","N/A","N/A");
								if(($hostAPIVersion eq '4.1.0' || $hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') && $ds->summary->type eq 'VMFS') {
									$iormEnable = ($ds->iormConfiguration->enabled ? "YES" : "NO");
									$iormThres = ($ds->iormConfiguration->congestionThreshold ? $ds->iormConfiguration->congestionThreshold . " ms" : "N/A");
									if($hostAPIVersion eq '5.0.0' || $hostAPIVersion eq '5.1.0' || $hostAPIVersion eq '5.5.0') {
										$dsMaintMode = ($ds->summary->maintenanceMode ? "YES" : "NO");
										$iormAggDisable = ($ds->iormConfiguration->statsAggregationDisabled ? "YES" : "NO");
										$iormStatsCollEnable = ($ds->iormConfiguration->statsCollectionEnabled ? "YES" : "NO");
									}
								}
								$ds_row = "</td><td>".@$vmsInDS."</td><td>".(prettyPrintData($ds->summary->capacity,'B'))."</td><td>".$ds_used."</td><td>".prettyPrintData($ds->summary->freeSpace,'B')."</td>$perc_string<td>$ds_block</td><td>".$ds_ver."</td><td>".$ds->summary->type."</td><td>".$dsMaintMode."</td><td>".$iormEnable."</td><td>".$iormThres."</td><td>".$iormAggDisable."</td><td>".$iormStatsCollEnable."</td>";
							} else {
								$ds_row = "</td><td>".@$vmsInDS."</td><td>".(prettyPrintData($ds->summary->capacity,'B'))."</td><td>".$ds_used."</td><td>".prettyPrintData($ds->summary->freeSpace,'B')."</td>$perc_string<td>$ds_block</td><td>".$ds_ver."</td><td>".$ds->summary->type."</td>";
							}

							$datastore_row_info{$ds->info->name} = $ds_row;
						}
						$datastores{$ds->info->name} .= $host_name. "_" . $ctr++ .",";
					}
				}
			}
			######################
			# PORTGROUP
			######################
			if($HOST_PORTGROUP eq "yes") {
				my $portgroup_views = Vim::get_views (mo_ref_array => $local_host->network);
				foreach my $portgroup (sort {$a->summary->name cmp $b->summary->name} @$portgroup_views) {
					my $pg_row = "";
					if($portgroup->summary->accessible) {
						push @hosts_in_portgroups,$host_name;

						#logic to figure out which hosts can not see this portgroup
						my @intersection = ();
						my @difference = ();
						my %count = ();
						foreach my $element (@hosts_in_portgroups, @hosts_seen) { $count{$element}++ }
						foreach my $element (keys %count) {
							push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
						}
						if(@difference) {
							my $hosts_not_accessible = "";
							foreach (@difference) {
								$hosts_not_accessible .= $_." ";
							}
							if($demo eq "no") {
								$pg_row .= "<td bgcolor=\"#FF6666\">$hosts_not_accessible</td>";
							} else {
								$pg_row .= "<td bgcolor=\"#FF6666\">demo_mode</td>";
							}
						} else {
							$pg_row .= "<td bgcolor=\"#66FF99\">Accessible by all hosts in this cluster</td>";
						}
						$portgroup_row_info{$portgroup->name} = $pg_row;
					}
				}
			}
			######################
			# CACHE
			######################
			if($HOST_CACHE eq "yes" && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
				my $cacheMgr;
				eval { $cacheMgr = Vim::get_view (mo_ref => $local_host->configManager->cacheConfigurationManager); };
				if(!$@) {
					if($cacheMgr->cacheConfigurationInfo) {
						my $cacheConfig = $cacheMgr->cacheConfigurationInfo;
						my $cacheConcatString = "";

						foreach(@$cacheConfig) {
							my $cacheDS = Vim::get_view(mo_ref => $_->key, properties => ['name']);
							my $cacheSwap = &prettyPrintData($_->swapSize,'M');
							$cacheConcatString .= "<tr><td>".$host_name."</td><td>".$cacheDS->{'name'}."</td><td>".$cacheSwap . "</td></tr>\n";
						}
						$cacheString .= $cacheConcatString;
					}
				}
			}
			######################
			# MULTIPATH
			######################
			if($HOST_MULTIPATH eq "yes") {
				my $storageSys;
				eval { $storageSys = Vim::get_view (mo_ref => $local_host->configManager->storageSystem); };
				if(!$@) {
					my $luns = $storageSys->storageDeviceInfo->scsiLun;
					my $hbas = $storageSys->storageDeviceInfo->hostBusAdapter;
					my $mpLuns = $storageSys->storageDeviceInfo->multipathInfo->lun;

					$multipathString .= "\n<table border=\"1\"><tr><th colspan=3>".$local_host->name."</th></tr>";

					my $verbose;
					foreach my $mpLun (@$mpLuns) {
						my $paths = $mpLun->path;
						my $numPaths = scalar(@$paths);
						my $lun = find_by_key($luns, $mpLun->lun);

						my $pol = $mpLun->policy;
						my $polPrefer;
						if (defined($pol) && defined($pol->{prefer})) {
							$polPrefer = $pol->prefer;
						}
						my $cap = $lun->{capacity};
						my $deviceUuidPath = defined($lun->{uuid}) ? ("vml." . $lun->uuid) : "";
						$multipathString .= "<table border=\"1\">\n";
						$multipathString .= "<tr><th>".(defined($lun->{lunType}) ? $lun->lunType : "")." ".(defined($lun->{canonicalName}) ? $lun->canonicalName : "").($verbose ? " $deviceUuidPath" : "")." ".(defined($cap) ? " ( " . int($cap->block * $cap->blockSize / (1024*1024)) . " MB )" : " ( 0 MB )")." ==  # of Paths: ".$numPaths." Policy: ".((defined($pol) && defined($pol->{policy})) ? $pol->policy : "")."</th></tr>\n";

						foreach my $path (@$paths) {
							my $hba = find_by_key($hbas, $path->adapter);
							my $isFC = $hba->isa("HostFibreChannelHba");
							my $state = ($path->{pathState} ? (($path->pathState eq "active") ? "On active" : $path->pathState) : "");
							my $pciString = get_pci_string($hba);

							my $pathStateColor;
							if($path->{pathState} eq "dead") {
								$pathStateColor = $light_red;
							} elsif($path->{pathState} eq "disabled" || $path->{pathState} eq "standby") {
								$pathStateColor = $yellow;
							} else {
								$pathStateColor = $white;
							}
							if($demo eq "no") {
								$multipathString .= "<tr><td bgcolor=\"" . $pathStateColor . "\">".($isFC ? "FC" : "Local")." ".$pciString." ".($isFC ? $hba->nodeWorldWideName . "<->" . $hba->portWorldWideName : "")." ".$path->name." ".$state." ".((defined($polPrefer) && ($path->name eq $polPrefer)) ? "preferred" : "")."</td></tr>\n";
							} else {
								$multipathString .= "<tr><td bgcolor=\"" . $pathStateColor . "\">".($isFC ? "FC" : "Local")." ".$pciString." "."demo_mode <-> demo_mode "." ".$path->name." ".$state." ".((defined($polPrefer) && ($path->name eq $polPrefer)) ? "preferred" : "")."</td></tr>\n";
							}
						}
						$multipathString .= "</table><br/>\n";
					}
				}
			}
			######################
			# LOG
			######################
			if($HOST_LOG eq "yes") {
				my $logKey = "hostd";
				my ($diagMgr,$logData);
				eval { $diagMgr = Vim::get_view(mo_ref => $sc->diagnosticManager); };
				if($atype eq 'VirtualCenter') {
					$logData = $diagMgr->BrowseDiagnosticLog(key => $logKey, host => $local_host, start => "999999999");
				} else {
					$logData = $diagMgr->BrowseDiagnosticLog(key => $logKey, start => "999999999");
				}
				my $lineEnd = $logData->lineEnd;
				my $start = $lineEnd - $logcount;
				if($atype eq 'VirtualCenter') {
					$logData = $diagMgr->BrowseDiagnosticLog(key => $logKey, host => $local_host, start => $start,lines => $logcount);
				} else {
					$logData = $diagMgr->BrowseDiagnosticLog(key => $logKey, start => $start,lines => $logcount);
				}
				$logString .= "<tr><th colspan=3>".$host_name."</th></tr>\n";
				if ($logData->lineStart != 0) {
					my $logConcat = "";
					foreach my $line (@{$logData->lineText}) {
						if($demo eq "no") {
							$logConcat .= $line."<br/>";
						} else {
							$logConcat = "demo_mode";
						}
					}
					$logString .= "<tr><td>".$logConcat."</td></tr>\n";
				}
			}

			## END OF HOSTS ##
		}

		###############################################
		## HACK TO PRINT DVS,LUN,DATASTORE and PORTGRUP  ##
		###############################################
		if($HOST_DVS eq "yes") {
			foreach(@dvs) {
				$dvsString .= $_;
			}
			@dvs = ();
		}
		if($HOST_LUN eq "yes") {
			#logic to check which hosts can see all luns
			while ( my ($uuid, $value) = each(%luns) ) {
				my @pairs = split(',',$value);
				my $pair_count = @pairs;
				my @hosts_to_luns = ();
				for (my $x=0;$x < $pair_count;$x++) {
					(my $hostname,my $vmhba) = split('_',$pairs[$x],2);
					push @hosts_to_luns, $hostname;
				}
				#logic to figure out which hosts can not see this lun
				my @intersection = ();
				my @difference = ();
				my %count = ();
				foreach my $element (@hosts_to_luns, @hosts_seen) { $count{$element}++ }
				foreach my $element (keys %count) {
					push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
				}

				my $print_string = "";
				if(@difference) {
					foreach (@difference) {
						$print_string .= $_." ";
					}
				}
				if($print_string eq '') {
					$print_string = "<td bgcolor=\"#66FF99\">Accessible by all hosts in this cluster</td>";
				} else {
					$print_string = "<td bgcolor=\"#FF6666\">".$print_string."</td>";
				}
				$lun_row_info{$uuid} .= $print_string;
				@hosts_to_luns = ();
			}

			foreach my $lun ( sort keys %lun_row_info ) {
				my $value = $lun_row_info{$lun};
				$lunString .= "<tr><td>".$lun."</td>".$value."</tr>\n";
			}
			(%luns,%lun_row_info) = ();
		}
		if($HOST_DATASTORE eq "yes") {
			#logic to check which hosts can see all datastores
			while ( my ($ds, $value) = each(%datastores) ) {
				my @pairs = split(',',$value);
				my $pair_count = @pairs;
				my @hosts_to_datastores = ();
				for (my $x=0;$x < $pair_count;$x++) {
					(my $hostname,my $count) = split('_',$pairs[$x],2);
					push @hosts_to_datastores, $hostname;
				}
				#logic to figure out which hosts can not see this datastore
				my @intersection = ();
				my @difference = ();
				my %count = ();
				foreach my $element (@hosts_to_datastores, @hosts_seen) { $count{$element}++ }
				foreach my $element (keys %count) {
					push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
				}

				my $print_string = "";
				if(@difference) {
					foreach (@difference) {
						$print_string .= $_." ";
					}
				}
				if($print_string eq '') {
					$print_string = "<td bgcolor=\"#66FF99\">Accessible by all hosts in this cluster</td>";
				} else {
					$print_string = "<td bgcolor=\"#FF6666\">".$print_string."</td>";
				}
				$datastore_row_info{$ds} .= $print_string;
				@hosts_to_datastores = ();
			}

			for my $datastore ( sort keys %datastore_row_info ) {
				my $value = $datastore_row_info{$datastore};
				$datastoreString .= "<tr><td>".$datastore."</td>".$value."</tr>\n";
			}
			(%datastores,%datastore_row_info) = ();
		}
		if($HOST_PORTGROUP eq "yes") {
			for my $portgroup ( sort keys %portgroup_row_info ) {
				my $value = $portgroup_row_info{$portgroup};
				if($demo eq "no") {
					$portgroupString .= "<tr><td>".$portgroup."</td>".$value."</tr>\n";
				} else {
					$portgroupString .= "<tr><td>demo_mode</td>".$value."</tr>\n";
				}
			}
			(%portgroup_row_info) = ();
		}

		## Executed outside of the hosts ##

		######################
		# TASK
		######################
		if($HOST_TASK eq "yes") {
			my $taskMgr;
			eval { $taskMgr = Vim::get_view(mo_ref => $sc->taskManager); };
			if(!$@) {
				my $tasks = Vim::get_views(mo_ref_array => $taskMgr->recentTask);
				foreach(@$tasks) {
					my $progress = $_->info->progress;
					if(!defined($progress)) {
						$progress = "COMPLETED";
					}
					$taskString .= "<tr><td>".$_->info->descriptionId."</td><td>".$_->info->queueTime."</td><td>".($_->info->startTime ? $_->info->startTime : "N/A")."</td><td>".($_->info->completeTime ? $_->info->completeTime : "N/A")."</td><td>".$progress."</td><td>".$_->info->state->val."</td></tr>\n";
				}
			}
		}

		@hosts_seen = ();
		@datastores_seen = ();
		@hosts_in_portgroups = ();
		&buildHostReport($cluster_name,$cluster_count,$type,$atype,$aversion);
	}
}

sub buildHostReport {
	my ($cluster_name,$cluster_count,$type,$atype,$aversion) = @_;

	my ($hostTag,$hostTagShort,$table_host_conf) = ("","","");

	if($HOST_STATE eq "yes" && $stateString ne "") {
		$hostTag = "ESX/ESXi State-$cluster_count";
		$hostTagShort = "ESX/ESXi State";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";

		if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_host_conf .= "<tr><th>HOSTNAME</th><th>OVERALL STATUS</th><th>POWER STATE</th><th>BOOT TIME</th><th>UPTIME</th><th>HA STATE</th><th>CONNECTION STATE</th><th>MAINTENANCE MODE</th><th>STANDBY MODE</th><th>VMOTION ENABLED</th><th>VERSION</th></tr>\n";
		} else {
			$table_host_conf .= "<tr><th>HOSTNAME</th><th>OVERALL STATUS</th><th>POWER STATE</th><th>BOOT TIME</th><th>CONNECTION STATE</th><th>MAINTENANCE MODE</th><th>VMOTION ENABLED</th><th>VERSION</th></tr>\n";
		}

		$table_host_conf .= $stateString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$stateString) = ("","");
	}
	if($HOST_MGMT eq "yes" && $mgmtString ne "") {
		$hostTag = "ESX/ESXi Management Info-$cluster_count";
		$hostTagShort = "ESX/ESXi Management Info";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_host_conf .= "<tr><th>HOSTNAME</th><th>vCenter</th><th>LOCKDOWN MODE ENABLED</th><th>COS VMDK</th><th>UUID</th><th>SERVICE CONSOLE MEM</th></tr>\n";
		} else {
			$table_host_conf .= "<tr><th>HOSTNAME</th><th>vCenter</th><th>LOCKDOWN MODE ENABLED</th><th>UUID</th><th>SERVICE CONSOLE MEM</th></tr>\n";
		}

		$table_host_conf .= $mgmtString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$mgmtString) = ("","");
	}
	if($HOST_HARDWARE_CONFIGURATION eq "yes" && $hardwareConfigurationString ne "") {
		$hostTag = "ESX/ESXi Hardware Configuration-$cluster_count";
		$hostTagShort = "ESX/ESXi Hardware Configuration";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_host_conf .= "<tr><th>HOSTNAME</th><th>VENDOR</th><th>ADDITIONAL VENDOR INFO</th><th>MODEL</th><th>CPU INFO</th><th>SMC PRESENT</th><th>HT AVAILABLE</th><th>CPU SPEED</th><th>CPU USAGE</th><th>PROCESSOR SOCKETS</th><th>CORES PER SOCKET</th><th>LOGICAL CORES</th><th>MEMORY</th><th>MEMORY USAGE</th><th>NIC(s)</th><th>HBA(s)</th></tr>\n";
		} else {
			$table_host_conf .= "<tr><th>HOSTNAME</th><th>VENDOR</th><th>ADDITIONAL VENDOR INFO</th><th>MODEL</th><th>CPU INFO</th><th>HT AVAILABLE</th><th>CPU SPEED</th><th>CPU USAGE</th><th>PROCESSOR SOCKETS</th><th>CORES PER SOCKET</th><th>LOGICAL CORES</th><th>MEMORY</th><th>MEMORY USAGE</th><th>NIC(s)</th><th>HBA(s)</th></tr>\n";
		}

		$table_host_conf .= $hardwareConfigurationString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$hardwareConfigurationString) = ("","");
	}
	if($HOST_HEALTH eq "yes" && $healthHardwareString ne "") {
		$hostTag = "ESX/ESXi Health Hardware Status-$cluster_count";
		$hostTagShort = "ESX/ESXi Health Hardware Status";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>COMPONENT</th><th>STATUS</th></tr>\n";

		$table_host_conf .= $healthHardwareString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$healthHardwareString) = ("","");
	}
	if($HOST_HEALTH eq "yes" && $healthSoftwareString ne "") {
		$hostTag = "ESX/ESXi Health Software Status-$cluster_count";
		$hostTagShort = "ESX/ESXi Health Software Status";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<a href=\"javascript:showHide('div$cluster_count')\">Click here for more detail info</a>\n";
		$table_host_conf .= "<div id=\"div$cluster_count\" style=\"display:none;thin solid;\">\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>SENSOR NAME</th><th>READING</th><th>STATUS</th></tr>\n";

		$table_host_conf .= $healthSoftwareString;
		$table_host_conf .= "</table>\n";
		$table_host_conf .= "</div>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$healthSoftwareString) = ("","");
	}
	if($HOST_PERFORMANCE eq "yes" || $hostperformance eq "yes" && $hostPerfString ne "") {
		$hostTag = "ESX/ESXi Performance-$cluster_count";
		$hostTagShort = "ESX/ESXi Performance";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>HOST</th><th>cpu.usagemhz.average</th><th>cpu.usage.average</th><th>mem.active.average</th><th>mem.usage.average</th></tr>\n";

		$table_host_conf .= $hostPerfString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$hostPerfString) = ("","");
	}
	if($HOST_NIC eq "yes" && $nicString ne "") {
		$hostTag = "ESX/ESXi NIC(s)-$cluster_count";
		$hostTagShort = "ESX/ESXi NIC(s)";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>HOST</th><th>DEVICE</th><th>PCI</th><th>DRIVER</th><th>DUPLEX</th><th>SPEED</th><th>WOL ENABLED</th><th>MAC</th></tr>\n";

		$table_host_conf .= $nicString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$nicString) = ("","");
	}
	if($HOST_HBA eq "yes" && $hbaString ne "") {
		$hostTag = "ESX/ESXi HBA(s)-$cluster_count";
		$hostTagShort = "ESX/ESXi HBA(s)";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>HOST</th><th>HBA TYPE</th><th>DEVICE</th><th>PCI</th><th>MODEL</th><th>DRIVER</th><th>STATUS</th><th>ADDITIONAL INFO</th></tr>\n";

		$table_host_conf .= $hbaString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$hbaString) = ("","");
	}
	if($HOST_ISCSI eq "yes" && $iscsiString ne "" && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		$hostTag = "ESX/ESXi iSCSI-$cluster_count";
		$hostTagShort = "ESX/ESXi iSCSI";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>HOST</th><th>VNIC</th><th>IP ADDRESS</th><th>NETMASK</th><th>MAC ADDRESS</th><th>MTU</th><th>TSO ENABLED</th><th>SPEED</th></th><th>PNIC</th><th>PORTGROUP</th><th>VSWITCH</th><th>SWITCH UUID</th><th>PATH STATUS</th></tr>\n";

		$table_host_conf .= $iscsiString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$iscsiString) = ("","");
	}
	if($HOST_CAPABILITY eq "yes" && $capString ne "") {
		$hostTag = "ESX/ESXi Capabilitie(s)-$cluster_count";
		$hostTagShort = "ESX/ESXi Capabilitie(s)";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";

		if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_host_conf .= "<tr><th>HOST</th><th>MAX RUNNING VMS SUPPORT</th><th>MAX VCPUS SUPPORT</th><th>VMFS VERSIONS SUPPORT</th><th>FT SUPPORT</th><th>IPMI SUPPORT</th><th>TPM SUPPORT</th><th>HV SUPPORT</th><th>IORM SUPPORT</th><th>DIRECTPATH G2 SUPPORT</th><th>STORAGE HW ACCELERATION SUPPORT</th><th>SSL THUMBPRINT AUTH SUPPORT</th></tr>\n";
		} elsif($aversion eq '4.1.0') {
			$table_host_conf .= "<tr><th>HOST</th><th>FT SUPPORT</th><th>IPMI SUPPORT</th><th>TPM SUPPORT</th><th>HV SUPPORT</th><th>IORM SUPPORT</th><th>DIRECTPATH G2 SUPPORT</th><th>STORAGE HW ACCELERATION SUPPORT</th><th>SSL THUMBPRINT AUTH SUPPORT</th></tr>\n";
		} else {
			$table_host_conf .= "<tr><th>HOST</th><th>FT SUPPORT</th><th>IPMI SUPPORT</th><th>TPM SUPPORT</th><th>HV SUPPORT</th><th>SSL THUMBPRINT AUTH SUPPORT</th></tr>\n";
		}

		$table_host_conf .= $capString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$capString) = ("","");
	}
	if($HOST_CONFIGURATION eq "yes" && $configString ne "") {
		$hostTag = "ESX/ESXi Configuration(s)-$cluster_count";
		$hostTagShort = "ESX/ESXi Configuration(s)";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";

		$table_host_conf .= $configString;
		#$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$configString) = ("","");
	}
	if($HOST_ADVOPT eq "yes" && $advString ne "") {
		$hostTag = "ESX/ESXi Advanced Options-$cluster_count";
		$hostTagShort = "ESX/ESXi Advanced Options";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";

		if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_host_conf .= "<tr><th>HOST</th><th>Disk.UseDeviceReset</th><th>Disk.UseLunReset</th><th>Disk.SchedNumReqOutstanding</th><th>Sc
si.ConflictRetries</th><th>NFS.MaxVolumes</th><th>SendBufferSize</th><th>ReceiveBufferSize</th><th>Net.TcpipHeapSize</th><th>NFS.HeartbeatFrequency</th><th>N
FS.HeartbeatTimeout</th><th>NFS.HeartbeatMaxFailures</th><th>VMkernel.Boot.techSupportMode</th><th>VMFS3.HardwareAcceleratedLocking</th><th>DataMover.Hardwar
eAcceleratedMove</th><th>DataMover.HardwareAcceleratedInit</th></tr>\n";
		} else {
			$table_host_conf .= "<tr><th>HOST</th><th>Disk.UseDeviceReset</th><th>Disk.UseLunReset</th><th>Disk.SchedNumReqOutstanding</th><th>Sc
si.ConflictRetries</th><th>NFS.MaxVolumes</th><th>SendBufferSize</th><th>ReceiveBufferSize</th><th>Net.TcpipHeapSize</th><th>NFS.HeartbeatFrequency</th><th>N
FS.HeartbeatTimeout</th><th>NFS.HeartbeatMaxFailures</th><th>VMkernel.Boot.techSupportMode</th></tr>\n";
		}

		$table_host_conf .= $advString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$advString) = ("","");
	}
	if($HOST_ADVOPT eq "yes" && $agentString ne "" && $atype eq "VirtualCenter"  && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		$hostTag = "ESX/ESXi Host Agent Settings-$cluster_count";
		$hostTagShort = "ESX/ESXi Host Agent Settings";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>HOST</th><th>AGENT VM DATASTORE</th><th>AGENT VM NETWORK</th></tr>\n";
		$table_host_conf .= $agentString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$agentString) = ("","");
	}
	if($HOST_NUMA eq "yes" && $numaString ne "") {
		$hostTag = "ESX/ESXi NUMA-$cluster_count";
		$hostTagShort = "ESX/ESXi NUMA";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>HOST</th><th># NODES</th><th>TYPE</th><th>NUMA NODE INFO</th></tr>\n";

		$table_host_conf .= $numaString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$numaString) = ("","");
	}
	if($HOST_CDP eq "yes" && $cdpString ne "") {
		$hostTag = "ESX/ESXi CDP-$cluster_count";
		$hostTagShort = "ESX/ESXi CDP";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>HOST</th><th>DEVICE</th><th>MGMT ADDRESS</th><th>DEVICE ADDRESS</th><th>IP PREFIX</th><th>LOCATION</th><th>SYSTEM NAME</th><th>SYSTEM VERSION</th><th>SYSTEM OID</th><th>PLATFORM</th><th>DEVICE ID</th><th>CDP VER</th><th>FULL DUPLEX</th><th>MTU</th><th>TIMEOUT</th><th>TTL</th><th>VLAN ID</th><th>SAMPLES</th></tr>\n";

		$table_host_conf .= $cdpString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$cdpString) = ("","");
	}
	if($HOST_DVS eq "yes" && $atype eq "VirtualCenter" && $dvsString ne "") {
		$hostTag = "ESX/ESXi Distributed vSwitch-$cluster_count";
		$hostTagShort = "ESX/ESXi Distributed vSwitch";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>NAME</th><th>DESCRIPTION</th><th>CONTACT INFO</th><th>VENDOR</th><th>VERSION</th><th>UUID</th><th>BUILD</th><th>
BUNDLE ID</th><th>BUNDLE BUILD</th><th>BUNDLE URL</th><th>FORWARDING CLASS</th><th>PORTS</th></tr>\n";

		$table_host_conf .= $dvsString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$numaString) = ("","");
	}
	if($HOST_LUN eq "yes" && $lunString) {
		$hostTag = "ESX/ESXi LUN(s)-$cluster_count";
		$hostTagShort = "ESX/ESXi LUN(s)";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";

		if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_host_conf .= "<tr><th>VOLUME UUID</th><th>DATASTORE</th><th>DISK_NAME</th><th>DEVICE_NAME</th><th>QUEUE DEPTH</th><th>vSTORAGE SUPPORT</th><th>STATUS</th><th>VENDOR</th><th>MODEL</th><th>HOST(s) NOT ACCESSIBLE TO LUN</tr>\n";
		} else {
			$table_host_conf .= "<tr><th>VOLUME UUID</th><th>DATASTORE</th><th>DISK_NAME</th><th>DEVICE_NAME</th><th>QUEUE DEPTH</th><th>STATUS</th><th>VENDOR</th><th>MODEL</th><th>HOST(s) NOT ACCESSIBLE TO LUN</tr>\n";
		}

		$table_host_conf .= $lunString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$lunString) = ("","");
	}
	if($HOST_DATASTORE eq "yes" && $datastoreString ne "") {
		$hostTag = "ESX/ESXi Datastore(s)-$cluster_count";
		$hostTagShort = "ESX/ESXi Datastore(s)";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\"><tr><td bgcolor=\"#CCCCCC\"><b>COLOR LEGEND</b></td><td bgcolor=\"$yellow\"><b>YELLOW < $YELLOW_WARN %</b></td><td bgcolor=\"$orange\"><b>ORANGE < $ORANGE_WARN %</b></td><td bgcolor=\"$red\"><b>RED < $RED_WARN %</b></td></tr></table>\n";
		$table_host_conf .= "<table border=\"1\">\n";

		if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_host_conf .= "<tr><th>DATASTORE</th><th># OF VMS</th><th>CAPACITY</th><th>CONSUMED</th><th>FREE</th><th>% FREE</th><th>BLOCK SIZE</th><th>VERSION</th><th>DS TYPE</th><th>MAINTENANCE MODE</th><th>IORM ENABLED</th><th>CONGESTION THRESHOLD</th><th>STATS AGGREGATION DIABLED</th><th>STATS COLLECTION ENABLED</th><th>HOST(s) NOT ACCESSIBLE TO DATASTORE</tr>\n";
		} else {
			$table_host_conf .= "<tr><th>DATASTORE</th><th># OF VMS</th><th>CAPACITY</th><th>CONSUMED</th><th>FREE</th><th>% FREE</th><th>BLOCK SIZE</th><th>VERSION</th><th>DS TYPE</th><th>HOST(s) NOT ACCESSIBLE TO DATASTORE</tr>\n";
		}

		$table_host_conf .= $datastoreString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$datastoreString) = ("","");
	}
	if($HOST_CACHE eq "yes" && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		$hostTag = "ESX/ESXi Cache Configuration-$cluster_count";
		$hostTagShort = "ESX/ESXi Cache Configuration";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>HOST</th><th>CACHE DATASTORE</th><th>SWAPSIZE</th></tr>\n";

		$table_host_conf .= $cacheString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$cacheString) = ("","");
	}
	if($HOST_PORTGROUP eq "yes" && $portgroupString ne "") {
		$hostTag = "ESX/ESXi Portgroup(s)-$cluster_count";
		$hostTagShort = "ESX/ESXi Portgroup(s)";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>PORTGROUP</th><th>HOST(s) NOT ACCESSIBLE TO PORTGROUP</th></tr>\n";

		$table_host_conf .= $portgroupString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$portgroupString) = ("","");
	}
	if($HOST_MULTIPATH eq "yes" && $multipathString ne "") {
		$hostTag = "ESX/ESXi Multipathing-$cluster_count";
		$hostTagShort = "ESX/ESXi Multipathing";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
###DEBUG
		#$table_host_conf .= "<table border=\"1\">\n";

		$table_host_conf .= $multipathString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$multipathString) = ("","");
	}
	if($HOST_LOG eq "yes" && $logString ne "") {
		$hostTag = "ESX/ESXi Hostd Logs-$cluster_count - Last $logcount lines";
		$hostTagShort = "ESX/ESXi Hostd Logs - Last $logcount lines";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";

		$table_host_conf .= $logString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$logString) = ("","");
	}
	if($HOST_TASK eq "yes" && $taskString ne "") {
		$hostTag = "ESX/ESXi Recent Tasks-$cluster_count";
		$hostTagShort = "ESX/ESXi Recent Tasks";

		push @host_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_host_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_host_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_host_conf .= "<table border=\"1\">\n";
		$table_host_conf .= "<tr><th>DESCRIPTION</th><th>QUEUE TIME</th><th>START TIME</th><th>COMPLETION TIME</th><th>PROGRESS</th><th>STATE</th></tr>\n";

		$table_host_conf .= $taskString;
		$table_host_conf .= "</table>\n";
		$hostString .= "<br/>".$table_host_conf;
		($table_host_conf,$numaString) = ("","");
	}

	print REPORT_OUTPUT $hostString;
	$hostString = "";
}

sub buildVMReport {
	my ($cluster_name,$cluster_count,$type,$atype,$aversion) = @_;
	my ($hostTag,$hostTagShort,$table_vm_conf) = ("","","");

	if($VM_STATE eq "yes" && $vmstateString ne "") {
		$hostTag = "VM State-$cluster_count";
		$hostTagShort = "VM State";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";

		if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>BOOTTIME</th><th>UPTIME</th><th>NOTES</th><th>OVERALL STATUS</th><th>HA PROTECTED</th><th>APP HEARTBEAT</th><th>CONNECTION STATE</th><th>POWER STATE</th><th>CONSOLIDATION NEEDED</th></tr>\n";
		} else {
		    $table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>NOTES</th><th>BOOTTIME</th><th>OVERALL STATUS</th><th>CONNECTION STATE</th><th>POWER STATE</th></tr>\n";
		}

		$table_vm_conf .= $vmstateString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmstateString) = ("","");
	}
	if($VM_CONFIG eq "yes" && $vmconfigString ne "") {
		$hostTag = "VM Configuration-$cluster_count";
		$hostTagShort = "VM Configuration";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";

		if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>vHW</th><th>HOSTNAME</th><th>UUID</th><th>FIRMWARE</th><th>OS</th><th># of vCPU</th><th>vMEM</th><th># of vDISK</th><th>vDISK</th><th># of vNIC</th><th>CPU RESERV</th><th>MEM RESERV</th><th>IS TEMPLATE</th></tr>\n";
		} else {
		    $table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>vHW</th><th>HOSTNAME</th><th>UUID</th><th>OS</th><th># of vCPU</th><th>vMEM</th><th># of vDISK</th><th>vDISK</th><th># of vNIC</th><th>CPU RESERV</th><th>MEM RESERV</th><th>IS TEMPLATE</th></tr>\n";
		}

		$table_vm_conf .= $vmconfigString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmconfigString) = ("","");
	}
	if($VM_STATS eq "yes" && $vmstatString ne "") {
		$hostTag = "VM Statistics-$cluster_count";
		$hostTagShort = "VM Statistics";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";

		if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
			$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>CPU USAGE</th><th>MEM USAGE</th><th>MAX CPU USAGE</th><th>MAX MEM USAGE</th><th>ACTIVE MEM</th><th>HOST CONSUMED MEM</th><th>INITIAL MEM RESV OVERHEAD</th><th>INITIAL MEM SWAP RESV OVERHEAD</th><th>MEM OVERHEAD</th><th>MEM BALLON</th><th>COMPRESSED MEM</th></tr>\n";
		} else {
			$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>CPU USAGE</th><th>MEM USAGE</th><th>MAX CPU USAGE</th><th>MAX MEM USAGE</th><th>ACTIVE MEM</th><th>HOST CONSUMED MEM</th><th>MEM OVERHEAD</th><th>MEM BALLON</th></tr>\n";
		}

		$table_vm_conf .= $vmstatString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmstatString) = ("","");
	}
	if($VM_RESOURCE_ALLOCATION eq "yes" && $vmrscString ne "") {
		$hostTag = "VM Resource Allocation-$cluster_count";
		$hostTagShort = "VM Resource Allocation";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>LAST MODIFIED</th><th>CPU RESERVATION</th><th>CPU LIMITS</th><th>CPU SHARE</th><th>CPU SHARE LEVEL</th><th>CPU EXPANDABLE RESERVATION</th><th>CPU OVERHEAD LIMIT</th><th>MEM RESERVATION</th><th>MEM LIMITS</th><th>MEM SHARE</th><th>MEM SHARE LEVEL</th><th>MEM EXPANDABLE RESERVATION</th><th>MEM OVERHEAD LIMIT</th></tr>\n";

		$table_vm_conf .= $vmrscString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmrscString) = ("","");
	}
	if($VM_PERFORMANCE eq "yes" || $vmperformance eq "yes" && $vmPerfString ne "") {
		$hostTag = "VM Performance-$cluster_count";
		$hostTagShort = "VM Performance";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>VM</th><th>cpu.usagemhz.average</th><th>cpu.usage.average</th><th>cpu.ready.summation</th><th>mem.active.average</th><th>mem.usage.average</th><th>cpu.vmmemctl.average</th</tr>\n";

		$table_vm_conf .= $vmPerfString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmPerfString) = ("","");
	}
	if($VM_FT eq "yes" && $vmftString ne "") {
		$hostTag = "VM Fault Tolerance-$cluster_count";
		$hostTagShort = "VM Fault Tolerance";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>FT STATE</th><th>ROLE</th><th>INSTANCE UUIDS</th><th>FT SECONDARY LATENCY</th><th>FT BANDWIDTH</th></tr>\n";

		$table_vm_conf .= $vmftString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmftString) = ("","");
	}
	if($VM_EZT eq "yes" && $vmeztString ne "" && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		$hostTag = "VM Eagerzeroed Thick (EZT) Provisioned-$cluster_count";
		$hostTagShort = "VM Eagerzeroed Thick (EZT) Provisioned";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>LABEL</th><th>EZT VMDK(s)</th><th>CAPACITY</th></tr>\n";

		$table_vm_conf .= $vmeztString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmeztString) = ("","");
	}
	if($VM_EZT eq "yes" && $vmeztString ne "" && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		$hostTag = "VM Eagerzeroed Thick (EZT) Provisioned-$cluster_count";
		$hostTagShort = "VM Eagerzeroed Thick (EZT) Provisioned";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>LABEL</th><th>EZT VMDK(s)</th><th>CAPACITY</th></tr>\n";

		$table_vm_conf .= $vmeztString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmeztString) = ("","");
	}
	if($VM_THIN eq "yes" && $vmthinString ne "") {
		$hostTag = "VM Thin Provisioned-$cluster_count";
		$hostTagShort = "VM Thin Provisioned";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>LABEL</th><th>THIN VMDK(s)</th><th>CAPACITY</th></tr>\n";

		$table_vm_conf .= $vmthinString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmthinString) = ("","");
	}
	if($VM_DEVICE eq "yes" && $vmdeviceString ne "") {
		$hostTag = "VM Device(s)-$cluster_count";
		$hostTagShort = "VM Device(s)";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>OS</th><th>CDROM</th><th>CONTROLLER</th><th>DISK</th><th>ETHERNET CARD</th><th>FLOPPY</th><th>KEYBOARD</th><th>VIDEO CARD</th><th>VMCI</th><th>VMIROM</th><th>PARALLEL PORT</th><th>PCI PASSTHROUGH</th><th>POINTING DEVICE</th><th>SCSI PASSTHROUGH</th><th>SERIAL PORT</th><th>SOUND CARD</th><th>USB</th></tr>\n";

		$table_vm_conf .= $vmdeviceString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmdeviceString) = ("","");
	}
	if($VM_STORAGE eq "yes" && $vmstorageString ne "") {
		$hostTag = "VM Storage-$cluster_count";
		$hostTagShort = "VM Storage";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\"><tr><td bgcolor=\"#CCCCCC\"><b>COLOR LEGEND</b></td><td bgcolor=\"$yellow\"><b>YELLOW < $YELLOW_WARN %</b></td><td bgcolor=\"$orange\"><b>ORANGE < $ORANGE_WARN %</b></td><td bgcolor=\"$red\"><b>RED < $RED_WARN %</b></td></tr></table>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th><table border=\"1\"><tr><td><b>DISK INFO</b></td><td><b>FREE SPACE</b></td><td><b>CAPACITY</b></td><td><b>% FREE</b></td></tr></table></th></tr>\n";

		$table_vm_conf .= $vmstorageString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmstorageString) = ("","");
	}
	if($VM_NETWORK eq "yes" && $vmnetworkString ne "") {
		$hostTag = "VM Network-$cluster_count";
		$hostTagShort = "VM Network";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>IP ADDRESS(s)</th><th>MAC ADDRESS(s)</th><th>PORTGROUP(s)</th><th>CONNECTED</th></tr>\n";

		$table_vm_conf .= $vmnetworkString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmnetworkString) = ("","");
	}
	if($VM_SNAPSHOT eq "yes" && $vmsnapString ne "") {
		$hostTag = "VM Snapshots-$cluster_count";
		$hostTagShort = "VM Snapshots";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>SNAPSHOT NAME</th><th>SNAPSHOT DESC</th><th>CREATED</th><th>STATE</th><th>QUIESCED</th></tr>\n";

		$table_vm_conf .= $vmsnapString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmsnapString) = ("","");
	}
	if($VM_DELTA eq "yes" && $vmdeltaString ne "") {
		$hostTag = "VM Deltas-$cluster_count";
		$hostTagShort = "VM Deltas";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\"><tr><td bgcolor=\"#CCCCCC\"><b>COLOR LEGEND</b></td><td bgcolor=\"$yellow\"><b>YELLOW > $SNAPSHOT_YELLOW_WARN days</b></td><td bgcolor=\"$orange\"><b>ORANGE > $SNAPSHOT_ORANGE_WARN days</b></td><td bgcolor=\"$red\"><b>RED > $SNAPSHOT_RED_WARN days</b></td></tr></table>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>DATASTORE</th><th>VM DELTA</th><th>AGE</th><th>SIZE</th><th>CREATED</th></tr>\n";

		$table_vm_conf .= $vmdeltaString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmdeltaString) = ("","");
	}
	if($VM_CDROM eq "yes" && $vmcdString ne "") {
		$hostTag = "VM Mounted CD-ROM-$cluster_count";
		$hostTagShort = "VM Mounted CD-ROM";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>ISO</th></tr>\n";

		$table_vm_conf .= $vmcdString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmcdString) = ("","");
	}
	if($VM_FLOPPY eq "yes" && $vmflpString ne "") {
		$hostTag = "VM Mounted Floppy-$cluster_count";
		$hostTagShort = "VM Mounted Floppy";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>IMG</th></tr>\n";

		$table_vm_conf .= $vmflpString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmflpString) = ("","");
	}
	if($VM_TOOL eq "yes" && $vmtoolString) {
		$hostTag = "VM VMware Tools-$cluster_count";
		$hostTagShort = "VM VMware Tools";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>VERSION</th><th>RUNNING STATUS</th><th>VERSION STATUS</th><th>UPGRADE POLICY</th><th>SYNC TIME W/HOST</th></tr>\n";

		$table_vm_conf .= $vmtoolString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmtoolString) = ("","");
	}
	if($VM_RDM eq "yes" && $vmrdmString ne "") {
		$hostTag = "VM RDMs-$cluster_count";
		$hostTagShort = "VM RDMs";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>COMPAT MODE</th><th>DEVICE</th><th>DISK MODE</th><th>LUN UUID</th><th>VIRTUAL DISK UUID</th></tr>\n";

		$table_vm_conf .= $vmrdmString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmrdmString) = ("","");
	}
	if($VM_NPIV eq "yes" && $vmnpivString ne "") {
		$hostTag = "VM NPIV-$cluster_count";
		$hostTagShort = "VM NPIV";

		push @vm_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$table_vm_conf .= "<a name=\"$hostTag\"></a>\n";
		$table_vm_conf .= "<h3>$hostTagShort:</h3>\n";
		$table_vm_conf .= "<table border=\"1\">\n";
		$table_vm_conf .= "<tr><th>HOST</th><th>VM</th><th>NODE WWN</th><th>PORT WWN</th><th>GENERATED FROM</th><th>DESIRED NODE WWN</th><th>DESIRED PORT WWN</th></tr>\n";

		$table_vm_conf .= $vmnpivString;
		$table_vm_conf .= "</table>\n";
		$vmString .= "<br/>".$table_vm_conf;
		($table_vm_conf,$vmnpivString) = ("","");
	}

	print REPORT_OUTPUT $vmString;
	$vmString = "";
}

sub printClusterSummary {
	my ($local_cluster,$cluster_count,$atype,$aversion) = @_;

	my $cluster_name = $local_cluster->name;
	my $cluster_health = $local_cluster->overallStatus->val;
	my $cluster_host_cnt = $local_cluster->summary->numHosts;
	my $cluster_avail_host = $local_cluster->summary->numEffectiveHosts;
	my $cluster_cpu_cnt = prettyPrintData($local_cluster->summary->totalCpu,'MHZ');
	my $cluster_mem_cnt = prettyPrintData($local_cluster->summary->totalMemory,'B');
	my $cluster_avail_cpu = prettyPrintData($local_cluster->summary->effectiveCpu,'MHZ');
	my $cluster_avail_mem = prettyPrintData($local_cluster->summary->effectiveMemory,'M');
	my $cluster_drs = $local_cluster->configuration->drsConfig->enabled;
	my $cluster_ha = $local_cluster->configuration->dasConfig->enabled;
	my $cluster_dpm = $local_cluster->configurationEx->dpmConfigInfo->enabled;
	my $cluster_vm_mon = $local_cluster->configuration->dasConfig->vmMonitoring;
	my $cluster_host_mon = $local_cluster->configuration->dasConfig->hostMonitoring;
	my $vmotions = $local_cluster->summary->numVmotions;
	my ($mem_perc_string,$cpu_perc_string,$evc,$spbm,$hbDSPolicy) = ("","","DISABLED","N/A","N/A");
	my $curr_bal = ($local_cluster->summary->currentBalance ? ($local_cluster->summary->currentBalance/1000) : "N/A");
	my $tar_bal = ($local_cluster->summary->targetBalance ? ($local_cluster->summary->targetBalance/1000) : "N/A");

	if($local_cluster->summary->currentEVCModeKey) {
		$evc = $local_cluster->summary->currentEVCModeKey;
	}

	if($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
		if(defined($local_cluster->configurationEx->spbmEnabled)) {
			$spbm = $local_cluster->configurationEx->spbmEnabled ? "YES" : "NO";
		}
		if(defined($local_cluster->configurationEx->dasConfig->hBDatastoreCandidatePolicy)) {
			$hbDSPolicy = $local_cluster->configurationEx->dasConfig->hBDatastoreCandidatePolicy;
		}
	}

	###########################
	# CLUSTER SUMMARY
	###########################

	push @cluster_jump_tags,"CL<a href=\"#$cluster_name\">Cluster: $cluster_name</a><br/>\n";

	my $cluster_start .= "<a name=\"$cluster_name\"></a>\n";
	$cluster_start .= "<h2>Cluster: $cluster_name</h2>\n";
	my ($hostTag,$hostTagShort) = ("","");

	###########################
	# SUMMARY
	###########################
	if($CLUSTER_SUMMARY eq "yes") {
		$hostTag = "Cluster Summary-$cluster_name";
		$hostTagShort = "Cluster Summary";
		push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$cluster_start .= "<a name=\"$hostTag\"></a>\n";
		$cluster_start .= "<h3>Cluster Summary:</h3>\n";
		$cluster_start .= "<table border=\"1\">\n";
		$cluster_start .= "<tr><th>CLUSTER HEALTH</th><th>AVAILABLE HOST(s)</th><th># OF VMS</th><th>VM-TO-HOST RATIO</th><th>CURRENT BALANCE</th><th>TARGET BALANCE</th><th>AVAILABLE CPU</th><th>AVAILABLE MEM</th><th>DRS ENABLED</th><th>HA ENABLED</th><th>DPM ENABLED</th><th>EVC ENABLED</th><th>SPBM ENABLED</th><th># OF vMOTIONS</th></tr>\n";

		my $rp = Vim::get_view(mo_ref => $local_cluster->resourcePool, properties => ['vm']);
		my $vms = Vim::get_views(mo_ref_array => $rp->{'vm'}, properties => ['name']);
		my $num_of_vms = 0;
		if(@$vms ne 0) { $num_of_vms = @$vms; }

		my $vm_host_ratio = "N/A";
		if($cluster_avail_host eq 1 && ($num_of_vms ne 0 || $num_of_vms eq 1)) {
			$vm_host_ratio = $num_of_vms
		} elsif($num_of_vms eq 1) {
			$vm_host_ratio = $num_of_vms
		} elsif($num_of_vms ne 0 && $cluster_avail_host ne 0) {
			$vm_host_ratio = int($num_of_vms/$cluster_avail_host);
		} else {
			$vm_host_ratio =  $num_of_vms;
		}

		$cluster_start .= "<tr>";
		if($cluster_health eq 'gray' ) { $cluster_start .= "<td bgcolor=gray>UNKNOWN"; }
		if($cluster_health eq 'green' ) { $cluster_start .= "<td bgcolor=$green>CLUSTER OK"; }
		if($cluster_health eq 'red' ) { $cluster_start .= "<td bgcolor=red>CLUSTER HAS PROBLEM"; }
		if($cluster_health eq 'yellow' ) { $cluster_start .= "<td bgcolor=yellow>CLUSTER MIGHT HAVE PROBLEM"; }
		$cluster_start .= "<td>".$cluster_avail_host."/".$cluster_host_cnt."</td>";
		$cluster_start .= "<td>".$num_of_vms."</td>";
		$cluster_start .= "<td>".$vm_host_ratio."</td>";
		$cluster_start .= "<td>".$curr_bal."</td>";
		$cluster_start .= "<td>".$tar_bal."</td>";
		$cluster_start .= "<td>".$cluster_avail_cpu."</td>";
		$cluster_start .= "<td>".$cluster_avail_mem."</td>";
		$cluster_start .= "<td>".(($cluster_drs) ? "YES" : "NO")."</td>";
		$cluster_start .= "<td>".(($cluster_ha) ? "YES" : "NO")."</td>";
		$cluster_start .= "<td>".(($cluster_dpm) ? "YES" : "NO")."</td>";
		$cluster_start .= "<td>".$evc."</td>";
		$cluster_start .= "<td>".$spbm."</td>";
		$cluster_start .= "<td>".$vmotions."</td>";
		$cluster_start .= "</tr>\n</table>\n";
	}

	###########################
	# CLUSTER PERFORMANCE
	###########################
	if($CLUSTER_PERFORMANCE eq "yes" || $clusterperformance eq "yes") {
		my $clusterPerfString = &getCpuAndMemPerf($local_cluster);
		$cluster_start .= $clusterPerfString;
	}

	###########################
	# PRINT HA INFO
	###########################
	if($cluster_ha && $CLUSTER_HA eq "yes") {
		$hostTag = "HA Configurations-$cluster_name";
		$hostTagShort = "HA Configurations";

		push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$cluster_start .= "<a name=\"$hostTag\"></a>\n";
		$cluster_start .= "<h3>HA Configurations</h3>\n";
		$cluster_start .= "<table border=\"1\">\n";
		$cluster_start .= "<tr><th>FAILOVER LEVEL</th><th>ADMISSION CONTROL ENABLED</th><th>ISOLATION RESPONSE</th><th>RESTART PRIORITY</th><th>VM MONITORING</th><th>HOST MONITORING</th><th>HB DATASTORE POLICY</tr>\n";

		if(defined($local_cluster->configuration->dasConfig->admissionControlPolicy)) {
			my $admissionControlPolicy = $local_cluster->configuration->dasConfig->admissionControlPolicy;
			if($admissionControlPolicy->isa('ClusterFailoverHostAdmissionControlPolicy')) {
				if($admissionControlPolicy->failoverHosts) {
					my $failoverHosts = $admissionControlPolicy->failoverHosts;
					my $failoverHostString = "";
					foreach(@$failoverHosts) {
						my $fhost = Vim::get_view(mo_ref => $_, properties => ['name']);
						$failoverHostString .= $fhost->{'name'} . "<br/>";
					}
					$cluster_start .= "<td>".$failoverHostString."</td>";
				} else {
					$cluster_start .= "<td>N/A</td>";
				}
			}elsif($admissionControlPolicy->isa('ClusterFailoverLevelAdmissionControlPolicy')) {
				$cluster_start .= "<td>".$admissionControlPolicy->failoverLevel."</td>";
			}elsif($admissionControlPolicy->isa('ClusterFailoverResourcesAdmissionControlPolicy')) {
				$cluster_start .= "<td>".$admissionControlPolicy->cpuFailoverResourcesPercent."% CPU -- ".$admissionControlPolicy->memoryFailoverResourcesPercent." %MEM "."</td>";
			} else {
				$cluster_start .= "<td>N/A</td>";
			}
		} else {
			$cluster_start .= "<td>N/A</td>";
		}
		$cluster_start .= "<td>".(($local_cluster->configuration->dasConfig->admissionControlEnabled) ? "YES" : "NO")."</td>";
		$cluster_start .= "<td>".$local_cluster->configuration->dasConfig->defaultVmSettings->isolationResponse."</td>";
		$cluster_start .= "<td>".$local_cluster->configuration->dasConfig->defaultVmSettings->restartPriority."</td>";
		$cluster_start .= "<td>".$cluster_vm_mon."</td>";
		$cluster_start .= "<td>".$cluster_host_mon."</td>";
		$cluster_start .= "<td>".$hbDSPolicy."</td>";
		$cluster_start .= "</table>\n";

		my $haAdvInfo;
		eval { $haAdvInfo = $local_cluster->RetrieveDasAdvancedRuntimeInfo(); };
		if(!$@) {
			if($haAdvInfo) {
				my @configIssues = ();

				## HA ADV INFO ##
				$cluster_start .= "<h3>HA Advanced Runtime Info</h3>\n";
				$cluster_start .= "<table border=\"1\">\n";
				$cluster_start .= "<tr><th>SLOT SIZE</th><th>TOTAL SLOTS IN CLUSTER</th><th>USED SLOTS</th><th>AVAILABLE SLOTS</th><th>TOTAL POWERED ON VMS</th><th>TOTAL HOSTS</th><th>TOTAL GOOD HOSTS</th></tr>\n";

				if($haAdvInfo->isa('ClusterDasFailoverLevelAdvancedRuntimeInfo')) {
					$cluster_start .= "<td>".($haAdvInfo->slotInfo->cpuMHz ? $haAdvInfo->slotInfo->cpuMHz : "N/A"). " MHz -- ".($haAdvInfo->slotInfo->numVcpus ? $haAdvInfo->slotInfo->numVcpus : "N/A"). " vCPUs -- ".($haAdvInfo->slotInfo->memoryMB ? $haAdvInfo->slotInfo->memoryMB : "N/A")." MB</td>";
					$cluster_start .= "<td>".$haAdvInfo->totalSlots."</td>";
					$cluster_start .= "<td>".$haAdvInfo->usedSlots."</td>";
					$cluster_start .= "<td>".$haAdvInfo->unreservedSlots."</td>";
					$cluster_start .= "<td>".$haAdvInfo->totalVms."</td>";
					$cluster_start .= "<td>".$haAdvInfo->totalHosts."</td>";
					$cluster_start .= "<td>".$haAdvInfo->totalGoodHosts."</td>";
				} else {
					$cluster_start .= "<td>N/A</td>";
					$cluster_start .= "<td>N/A</td>";
					$cluster_start .= "<td>N/A</td>";
					$cluster_start .= "<td>N/A</td>";
					$cluster_start .= "<td>N/A</td>";
					$cluster_start .= "<td>N/A</td>";
					$cluster_start .= "<td>N/A</td>";
				}
				$cluster_start .= "</table>\n";

				## HA HEARTBEAT DATASTORE ##
				if(($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') && $haAdvInfo->heartbeatDatastoreInfo) {
					my $hahbInfo = $haAdvInfo->heartbeatDatastoreInfo;

					$hostTag = "Heartbeat Datastores-$cluster_name";
					$hostTagShort = "Heartbeat Datastores";

					push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

					$cluster_start .= "<a name=\"$hostTag\"></a>\n";
					$cluster_start .= "<h3>Heartbeat Datastores</h3>\n";
					$cluster_start .= "<table border=\"1\">\n";
					$cluster_start .= "<tr><th>DATASTORE</th><th>HOSTS MOUNTED</th></tr>\n";

					foreach(@$hahbInfo) {
						my $hbDSName = Vim::get_view(mo_ref => $_->datastore, properties => ['name']);
						my $hbHostMount = Vim::get_views(mo_ref_array=> $_->hosts, properties => ['name']);
						$cluster_start .= "<tr><td>".$hbDSName->{'name'}."</td><td>".@$hbHostMount."</td></tr>";
					}
					$cluster_start .= "</table>\n";
				}

				## HA HOSTS INFO ##
				if($haAdvInfo->dasHostInfo && $haAdvInfo->dasHostInfo->hostDasState) {
					$cluster_start .= "<h3>HA Host Info</h3>\n";
					$cluster_start .= "<table border=\"1\">\n";
					$cluster_start .= "<tr><th>HA PRIMARY HOSTS</th><th>HA SECONDARY HOSTS</th><th>NODE STATES</th></tr>\n";

					my ($nodeStates,$primHosts,$secondHosts,$dasstring) = ("","","","");
					my %primary = ();

					$cluster_start .= "<tr>";
					if($haAdvInfo->dasHostInfo->primaryHosts) {
						my $dashosts = $haAdvInfo->dasHostInfo->primaryHosts;
						foreach my $dasHost (@$dashosts) {
							if($demo eq "yes") {
								$dasHost = $host_name;
							}
							$primHosts .= $dasHost."<br/>";
							$primary{$dasHost} = "yes";
						}
						$cluster_start .= "<td>".$primHosts."</td>";
					}

					if($haAdvInfo->dasHostInfo->hostDasState) {
						$dasstring .= "<td><table border=\"1\"><th>NODE</th><th>CONFIG STATE</th><th>RUN STATE</th>";
						my $dasstates = $haAdvInfo->dasHostInfo->hostDasState;
						foreach(@$dasstates) {
							my $dasHost;
							if($demo eq "yes") {
								$dasHost = $host_name;
							} else {
								$dasHost = $_->name;
							}
							$dasstring .= "<tr><td>".$dasHost."</td><td>".$_->configState."</td><td>".$_->runtimeState."</td></tr>\n";
							if(!$primary{$dasHost}) {
								$secondHosts .= $dasHost."<br/>";
							}

							my $tmpHostMoRef = Vim::get_view(mo_ref => $_->host);
							if($tmpHostMoRef->configIssue) {
								my $hostConfigIssues = $tmpHostMoRef->configIssue;
								foreach(@$hostConfigIssues) {
									my $issue = $tmpHostMoRef->name . ";" . ($_->fullFormattedMessage ? $_->fullFormattedMessage : "N/A");
									push @configIssues, $issue;
								}
							}
						}

						$cluster_start .= "<td>".$secondHosts."</td>";
						$cluster_start .= $dasstring;
						$cluster_start .= "</table></td>";
					}
					$cluster_start .= "</tr>";

					$cluster_start .= "</table>\n";
					%primary = ();
				}

				if($local_cluster->configIssue) {
					my $clusterConfigIssues = $local_cluster->configIssue;
					foreach(@$clusterConfigIssues) {
						my $issue = $local_cluster->name . ";" . ($_->fullFormattedMessage ? $_->fullFormattedMessage : "N/A");
						push @configIssues, $issue;
					}
				}

				## HA CONFIGURATION ISSUE##
				if(@configIssues) {
					$cluster_start .= "<h3>HA Configuration Issues</h3>\n";
					$cluster_start .= "<table border=\"1\">\n";
					$cluster_start .= "<tr><th>ENTITY</th><th>HA ISSUE</th></tr>\n";

					foreach(@configIssues) {
						my ($configIssueEntity,$configIssueMsg) = split(';',$_);
						$cluster_start .= "<tr><td>".$configIssueEntity."</td><td>".$configIssueMsg."</td></tr>\n";
					}
					$cluster_start .= "</table></td>";
				}

				## HA ADV OPTIONS ##
				if($local_cluster->configurationEx->dasConfig->option) {
					$cluster_start .= "<h3>HA Advanced Configurations</h3>\n";
					$cluster_start .= "<table border=\"1\">\n";
					$cluster_start .= "<tr><th>ATTRIBUTE</th><th>VALUE</th></tr>\n";

					my $haadv_string = "";

					my $advHAOptions = $local_cluster->configurationEx->dasConfig->option;
					foreach(@$advHAOptions) {
						$haadv_string .= "<tr><td>".$_->key."</td><td>".$_->value."</td></tr>\n";
					}
					$cluster_start .= $haadv_string;
					$cluster_start .= "</table>\n";
				}
			}
		}

	}

	###########################
	# PRINT DRS INFO
	###########################
	if($cluster_drs && $CLUSTER_DRS eq "yes") {
		$hostTag = "DRS Configurations-$cluster_name";
		$hostTagShort = "DRS Configurations";

		push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$cluster_start .= "<a name=\"$hostTag\"></a>\n";
		$cluster_start .= "<h3>DRS Configurations</h3>\n";
		$cluster_start .= "<table border=\"1\">\n";
		$cluster_start .= "<tr><th>DRS BEHAVIOR</th><th>VMOTION RATE</th></tr>\n";

		$cluster_start .= "<tr><td>".$local_cluster->configuration->drsConfig->defaultVmBehavior->val."</td>";
		$cluster_start .= "<td>".$local_cluster->configuration->drsConfig->vmotionRate."</td>";
		$cluster_start .= "</tr></table>\n";

		## DRS ADV OPTIONS ##
		if($local_cluster->configurationEx->drsConfig->option) {
			$cluster_start .= "<h3>DRS Advanced Configurations</h3>\n";
			$cluster_start .= "<table border=\"1\">\n";
			$cluster_start .= "<tr><th>ATTRIBUTE</th><th>VALUE</th></tr>\n";

			my $drsadv_string = "";

			my $advHAOptions = $local_cluster->configurationEx->drsConfig->option;
			foreach(@$advHAOptions) {
				$drsadv_string .= "<tr><td>".$_->key."</td><td>".$_->value."</td></tr>\n";
			}
			$cluster_start .= $drsadv_string;
			$cluster_start .= "</table>\n";
		}
	}

	###########################
	# PRINT DPM INFO
	###########################
	if($cluster_dpm && $CLUSTER_DPM eq "yes") {
		$hostTag = "DPM Configurations-$cluster_name";
		$hostTagShort = "DPM Configurations";

		push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

		$cluster_start .= "<a name=\"$hostTag\"></a>\n";
		$cluster_start .= "<h3>DPM Configurations</h3>\n";
		$cluster_start .= "<table border=\"1\">\n";
		$cluster_start .= "<tr><th>DPM BEHAVIOR</th></tr><tr>\n";

		$cluster_start .= "<td>".$local_cluster->configurationEx->dpmConfigInfo->defaultDpmBehavior->val."</td>";
		$cluster_start .= "</tr></table>\n";
	}

	###########################
	# AFFINITY RULES
	###########################
	if($CLUSTER_AFFINITY eq "yes") {
		if($local_cluster->configurationEx->rule) {
			my $rules = $local_cluster->configurationEx->rule;

			$hostTag = "Affinity Rules-$cluster_name";
			$hostTagShort = "Affinity Rules";

			push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

			$cluster_start .= "<a name=\"$hostTag\"></a>\n";
			$cluster_start .= "<h3>Affinity Rules:</h3>\n";
			$cluster_start .= "<table border=\"1\">\n";
			if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
				$cluster_start .= "<tr><th>RULE NAME</th><th>RULE TYPE</th><th>ENABLED</th><th>VM(s)</th><th>COMPLIANT</th><th>MANDATORY</th><th>USER CREATED</th></tr>\n";
			} else {
				$cluster_start .= "<tr><th>RULE NAME</th><th>RULE TYPE</th><th>ENABLED</th><th>VM(s)</th></tr>\n";
			}

			foreach(sort {$a->name cmp $b->name} @$rules) {
				my $rule = $_;
				my $is_enabled = $rule->enabled;
				my $rule_name = $rule->name;
				my $rule_type = "CLUSTER-RULE";
				my $compliant;

				if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
					if($rule->inCompliance) {
						$compliant = "<td bgcolor=\"$green\">YES</td>";
					} else {
						$compliant = "<td bgcolor=\"$red\">NO</td>";
					}
				}

				if(ref($rule) eq 'ClusterAffinityRuleSpec') {
					$rule_type = "AFFINITY";
				}
				elsif (ref($rule) eq 'ClusterAntiAffinityRuleSpec') {
					$rule_type = "ANTI-AFFINITY";
				}
				my $listOfVMs = Vim::get_views(mo_ref_array => $_->{'vm'}, properties => ['name']);
				my $listOfVmsString = "";
				foreach(@$listOfVMs) {
					$listOfVmsString .= $_->{'name'}."<br/>";
				}
				if($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0') {
					$cluster_start .= "<tr><td>".$rule_name."</td><td>".$rule_type."</td><td>".(($is_enabled) ? "YES" : "NO")."</td><td>".$listOfVmsString."</td>".$compliant."<td>".($rule->mandatory ? "YES" : "NO")."</td><td>".($rule->userCreated ? "YES" : "NO")."</td></tr>\n";
				} else {
					$cluster_start .= "<tr><td>".$rule_name."</td><td>".$rule_type."</td><td>".(($is_enabled) ? "YES" : "NO")."</td><td>".$listOfVmsString."</td></tr>\n";
				}
			}
			$cluster_start .= "</table>\n";
		}
	}

	###########################
	# AFFINITY GROUP RULES
	###########################
	if($CLUSTER_GROUP eq "yes" && ($aversion eq '4.1.0' || $aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
		if($local_cluster->configurationEx->group) {
			my $groups = $local_cluster->configurationEx->group;

			$hostTag = "Affinity Group Rules-$cluster_name";
			$hostTagShort = "Affinity Group Rules";

			push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

			$cluster_start .= "<a name=\"$hostTag\"></a>\n";
			$cluster_start .= "<h3>Affinity Group Rules:</h3>\n";
			my ($drsHostsGroupString,$drsVMGroupString) = ("","");

			foreach(sort {$a->name cmp $b->name} @$groups) {
				if($_->isa('ClusterHostGroup')) {
					my $listOfHosts = Vim::get_views(mo_ref_array => $_->host, properties => ['name']);
					my $listOfHostsString = "";
					foreach(@$listOfHosts) {
						$listOfHostsString .= $_->{'name'}."<br/>";
					}
					$drsHostsGroupString .= "<tr><td>".$_->name."</td><td>".$listOfHostsString."</td></tr>\n";
				}elsif($_->isa('ClusterVmGroup')) {
					my $listOfVms = Vim::get_views(mo_ref_array => $_->vm, properties => ['name']);
					my $listOfVmsString = "";
					foreach(@$listOfVms) {
						$listOfVmsString .= $_->{'name'}."<br/>";
					}
					$drsVMGroupString .= "<tr><td>".$_->name."</td><td>".$listOfVmsString."</td></tr>\n";
				}
			}

			#HOST GROUP
			if($drsHostsGroupString ne "") {
				$cluster_start .= "<table border=\"1\">\n";
				$cluster_start .= "<tr><th>RULE NAME</th><th>HOST(s)</th></tr>\n";
				$cluster_start .= $drsHostsGroupString;
				$cluster_start .= "</table><br/>\n";
			}

			#VM GROUP
			if($drsVMGroupString ne "") {
				$cluster_start .= "<table border=\"1\">\n";
				$cluster_start .= "<tr><th>RULE NAME</th><th>VM(s)</th></tr>\n";
				$cluster_start .= $drsVMGroupString;
				$cluster_start .= "</table><br/>\n";
			}
		}

	}

	###########################
	# RESOURCE POOLS
	###########################
	my ($resource_pool_string,$vapp_string) = ("","");

	if($CLUSTER_VAPP eq "yes" || $CLUSTER_RP eq "yes") {
		my $root_rp = Vim::get_view (mo_ref => $local_cluster->resourcePool);
		my $resourcePools = $root_rp->resourcePool;

		foreach(@$resourcePools) {
			my $rp = Vim::get_view(mo_ref => $_);

			if($rp->isa('VirtualApp')) {
				my $vapp_name = $rp->name;
				my $anno = ($rp->vAppConfig->annotation ? $rp->vAppConfig->annotation : "N/A");

				my $ec = $rp->vAppConfig->entityConfig;
				my $vm_vapp_string = "";
				foreach(@$ec) {
					my $order = $_->startOrder;
					my $tag = $_->tag;
					$vm_vapp_string .= "<tr><td>".$tag."</td><td>".$order."</td></tr>\n";
				}
				$vapp_string .= "<tr><th colspan=2>".$vapp_name."</th><tr>\n";
				$vapp_string .= "<tr><th>VM</th><th>START ORDER</th></tr>\n";
				$vapp_string .= $vm_vapp_string."</tr>\n";
			} else {
				my $rp_name = $rp->name;
				my $rp_status = $rp->summary->runtime->overallStatus->val;
				if($rp_status eq 'gray') { $rp_status = "<td bgcolor=\"gray\">UNKNOWN</td>"; }
				elsif($rp_status eq 'green') { $rp_status = "<td bgcolor=\"$green\">GREEN</td>";  }
				elsif($rp_status eq 'red') { $rp_status = "<td bgcolor=\"$red\">RED</td>"; }
				elsif($rp_status eq 'yellow') { $rp_status = "<td bcolor=\"$yellow\">YELLOW</td>"; }
				my $rp_cpu_use = prettyPrintData($rp->summary->runtime->cpu->overallUsage,'MHZ');
				my $rp_cpu_max = prettyPrintData($rp->summary->runtime->cpu->maxUsage,'MHZ');
				my $rp_cpu_lim = prettyPrintData($rp->summary->config->cpuAllocation->limit,'MHZ');
				my $rp_cpu_rsv = prettyPrintData($rp->summary->config->cpuAllocation->reservation,'MHZ');
				my $rp_mem_use = prettyPrintData($rp->summary->runtime->memory->overallUsage,'B');
				my $rp_mem_max = prettyPrintData($rp->summary->runtime->memory->maxUsage,'B');
				my $rp_mem_lim = prettyPrintData($rp->summary->config->cpuAllocation->limit,'M');
				my $rp_mem_rsv = prettyPrintData($rp->summary->config->cpuAllocation->reservation,'M');
				my ($rp_cpu_shares,$rp_mem_shares) = ("N/A","N/A");
				if($rp->summary->config->cpuAllocation) {
					$rp_cpu_shares = ($rp->summary->config->cpuAllocation->shares->shares ? $rp->summary->config->cpuAllocation->shares->shares : "N/A");
				}
				if($rp->summary->config->memoryAllocation) {
					$rp_mem_shares = ($rp->summary->config->memoryAllocation->shares->shares ? $rp->summary->config->memoryAllocation->shares->shares : "N/A");
				}

				my $vmInRp = 0;
				if($rp->vm) {
					my $vmsInRp = Vim::get_views(mo_ref_array => $rp->vm, properties => ['name']);
					$vmInRp = scalar(@$vmsInRp);
				}

				my ($cpuUnitsPerVM,$memUnitsPerVM) = ("N/A","N/A");

				if($vmInRp != 0 && $rp_cpu_shares ne "N/A") {
					$cpuUnitsPerVM = floor($rp_cpu_shares/$vmInRp);
				}
				if($vmInRp != 0 && $rp_mem_shares ne "N/A") {
					$memUnitsPerVM = floor($rp_mem_shares/$vmInRp);
				}

				$resource_pool_string .= "<tr><td>".$rp_name."</td>";
				$resource_pool_string .= $rp_status;
				$resource_pool_string .= "<td>".$vmInRp."</td>";
				$resource_pool_string .= "<td>".$rp_cpu_shares."</td>";
				$resource_pool_string .= "<td>".$cpuUnitsPerVM."</td>";
				$resource_pool_string .= "<td>".$rp_mem_shares."</td>";
				$resource_pool_string .= "<td>".$memUnitsPerVM."</td>";
				$resource_pool_string .= "<td>".$rp_cpu_lim."</td>";
				$resource_pool_string .= "<td>".$rp_cpu_rsv."</td>";
				$resource_pool_string .= "<td>".$rp_mem_lim."</td>";
				$resource_pool_string .= "<td>".$rp_mem_rsv."</td>";
				$resource_pool_string .= "<td>".$rp_cpu_use."</td>";
				$resource_pool_string .= "<td>".$rp_cpu_max."</td>";
				$resource_pool_string .= "<td>".$rp_mem_use."</td>";
				$resource_pool_string .= "<td>".$rp_mem_max."</td></tr>\n";
			}
		}
	}

	if($CLUSTER_RP eq "yes") {
		if($resource_pool_string ne "") {
			$hostTag = "Resource Pool(s)-$cluster_name";
			$hostTagShort = "Resource Pool(s)";

			push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

			$cluster_start .= "<a name=\"$hostTag\"></a>\n";
			$cluster_start .= "<h3>Resource Pool(s):</h3>\n";
			$cluster_start .= "<table border=\"1\">\n";
			$cluster_start .= "<tr><th>POOL NAME</th><th>STATUS</th><th># of VM(s)</th><th>CPU SHARES</th><th>CPU UNITS PER/VM</th><th>MEM SHARES</th><th>MEM UNITS PER/VM</th><th>CPU LIMIT</th><th>CPU RESERVATION</th><th>MEM LIMIT</th><th>MEM RESERVATION</th><th>CPU USAGE</th><th>CPU MAX</th><th>MEM USAGE</th><th>MEM MAX</th></tr>\n";

			$cluster_start .= $resource_pool_string;
			$cluster_start .= "</table>\n";
		}
	}

	###########################
	# VAPPS
	###########################
	if($CLUSTER_VAPP eq "yes") {
		if($vapp_string ne "") {
			$hostTag = "vApp(s)-$cluster_name";
			$hostTagShort = "vApp(s)";

			push @cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";

			$cluster_start .= "<a name=\"$hostTag\"></a>\n";
			$cluster_start .= "<h3>vApp(s):</h3>\n";
			$cluster_start .= "<table border=\"1\">\n";

			$cluster_start .= $vapp_string;
			$cluster_start .= "</table>\n";
		}
	}

	#search datastore for delta files
	if($VM_DELTA eq "yes") {
		my $datastores = Vim::get_views(mo_ref_array => $local_cluster->datastore);
		foreach my $datastore (@$datastores) {
			if($datastore->summary->accessible) {
				my $dsbrowser = Vim::get_view(mo_ref => $datastore->browser);
				my $ds_path = "[" . $datastore->info->name . "]";
				my $file_query = FileQueryFlags->new(fileOwner => 0, fileSize => 1,fileType => 0,modification => 1);
				my $searchSpec = HostDatastoreBrowserSearchSpec->new(details => $file_query,matchPattern => ["*.vmsn", "*-delta.vmdk"]);
				my $search_res = $dsbrowser->SearchDatastoreSubFolders(datastorePath => $ds_path,searchSpec => $searchSpec);
				if ($search_res) {
					foreach my $result (@$search_res) {
						my $files = $result->file;
						if($files) {
							foreach my $file (@$files) {
								if($file->path =~ /-delta.vmdk/ ) {
									my ($vm_snapshot_date,$vm_snapshot_time) = split('T',$file->modification);
									my $todays_date = giveMeDate('YMD');
									chomp($todays_date);
									my $diff = days_between($vm_snapshot_date, $todays_date);
									my $snap_time = $vm_snapshot_date." ".$vm_snapshot_time;
									my $size = &prettyPrintData($file->fileSize,'B');

									my $snap_color_string = "";
									$snap_color_string = "<td>".$result->folderPath."</td><td>".$file->path."</td>";
									if($diff > $SNAPSHOT_YELLOW_WARN) {
										if($diff > $SNAPSHOT_RED_WARN) {
											 $snap_color_string .= "<td bgcolor=\"$red\">".$diff." days old</td>";
										}elsif($diff > $SNAPSHOT_ORANGE_WARN) {
											 $snap_color_string .= "<td bgcolor=\"$orange\">".$diff." days old</td>";
										}elsif($diff > $SNAPSHOT_YELLOW_WARN) {
											 $snap_color_string .= "<td bgcolor=\"$yellow\">".$diff." days old</td>";
										}
										$snap_color_string .= "<td>".$size."</td><td>".$snap_time."</td>";
										push @vmdeltas,$snap_color_string;
									}
								}
							}
						}
					}
				}
			}
		}
	}

	print REPORT_OUTPUT "<br/>".$cluster_start;
}

sub printDatacenterSummary {
	my ($local_datacenter,$dc_count,$atype,$aversion) = @_;

	my $datacenter_name = $local_datacenter->name;

	push @datastore_cluster_jump_tags,"CL<a href=\"#$datacenter_name\">Datacenter: $datacenter_name</a><br/>\n";

	my $datacenter_start .= "<a name=\"$datacenter_name\"></a>\n";
	$datacenter_start .= "<h2>Datacenter: $datacenter_name</h2>\n";
	my ($hostTag,$hostTagShort) = ("","");

	my ($storagePods,$dvs);

	if($DATASTORE_CLUSTER_SUMMARY eq "yes" || $DATASTORE_CLUSTER_POD_CONFIG eq "yes" || $DATASTORE_CLUSTER_POD_ADV_CONFIG eq "yes" || $DATASTORE_CLUSTER_POD_STORAGE eq "yes") {
		$storagePods = Vim::find_entity_views(view_type => 'StoragePod', begin_entity => $local_datacenter);
	}

	if($DVS_SUMMARY eq "yes" || $DVS_CAPABILITY eq "yes" || $DVS_CONFIG eq "yes") {
		$dvs = Vim::find_entity_views(view_type => 'DistributedVirtualSwitch', begin_entity => $local_datacenter);
	}

	###############
	# POD SUMMARY
	###############
	if($DATASTORE_CLUSTER_SUMMARY eq "yes" && @$storagePods gt 0) {
		$hostTag = "Datastore Cluster Summary-$datacenter_name";
		$hostTagShort = "Datastore Cluster Summary";
		push @datastore_cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";
		$datacenter_start .= "<a name=\"$hostTag\"></a>\n";
		$datacenter_start .= "<h3>Datastore Cluster Summary:</h3>\n";
		$datacenter_start .= "<table border=\"1\">\n";
		$datacenter_start .= "<tr><th>STORAGE POD NAME</th><th>NUMBER OF DATASTORES</th><th>NUMBER OF VMS</th><th>CAPACITY</th><th>FREE SPACE</th><th>LARGEST DATASTORE FREE SPACE</th></tr>\n";

		foreach my $pod (@$storagePods) {
			if(defined($pod->summary)) {
				my @podDatastores = ();
				my ($podDSCount,$podVMCount) = (0,0);
				# If a pod has no datastores, childEntity will be undef, so force an empty array.
				foreach my $ds ( defined($pod->childEntity) ? @{$pod->childEntity} : () ) {
					my $child_view = Vim::get_view(mo_ref => $ds);

					if($child_view->isa("Datastore")) {
						push @podDatastores, $child_view;
						my $vmsperds = Vim::get_views(mo_ref_array => $child_view->vm, properties => ['name']);
						$podVMCount += @$vmsperds;
						$podDSCount++;
					}
				}

				# find the largest datastore
				my $largestDatastoreSize = 0;
				my $largestDatastoreName = "";
				foreach(@podDatastores) {
					if($_->summary->freeSpace gt $largestDatastoreSize) {
						$largestDatastoreSize = $_->summary->freeSpace;
						$largestDatastoreName = $_->name;
					}
				}

				$datacenter_start .= "<tr><td>" . $pod->name . "</td><td>" . $podDSCount . "</td><td>" . $podVMCount . "</td><td>" . &prettyPrintData($pod->summary->capacity,'B') . "</td><td>" . &prettyPrintData($pod->summary->freeSpace,'B') . "</td><td>" . &prettyPrintData($largestDatastoreSize,'B') . " (" . $largestDatastoreName . ")</td></tr>\n";
			}
		}
		$datacenter_start .= "</table>\n";
	}

	###############
	# POD CONFIG
	###############
	if($DATASTORE_CLUSTER_POD_CONFIG eq "yes" && @$storagePods gt 0) {
		$hostTag = "Datastore Cluster Pod Config-$datacenter_name";
		$hostTagShort = "Datastore Cluster Pod Config";
		push @datastore_cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";
		$datacenter_start .= "<a name=\"$hostTag\"></a>\n";
		$datacenter_start .= "<h3>Datastore Cluster Pod Config:</h3>\n";
		$datacenter_start .= "<table border=\"1\">\n";
		$datacenter_start .= "<tr><th>STORAGE POD NAME</th><th>SDRS ENABLED</th><th>IO BALANCE ENABLED</th><th>IO BALANCE LATENCY THRESHOLD</th><th>IO LOAD BALANCE THRESHOLD</th><th>IO BALANCE INTERVAL</th><th>LOAD BALANCE SPACE UTILIZATION DIFFERENCE</th><th>SPACE UTILIZATION THRESHOLD</th><th>ENABLE INTRA-VM AFFINITY</th><th>DEFAULT VM BEHAVIOR</th></tr>\n";

		foreach my $pod (@$storagePods) {
			if(defined($pod->podStorageDrsEntry)) {
				my ($ioLatThres,$ioLBThres,$ioLBInt,$minSpaceUtiDiff,$spaceUtilDiff,$defIntraVMAff) = ("N/A","N/A","N/A","N/A","N/A","N/A");

				my $podConfig = $pod->podStorageDrsEntry->storageDrsConfig->podConfig;
				if(defined($podConfig->ioLoadBalanceConfig)) {
					if($podConfig->ioLoadBalanceConfig->ioLatencyThreshold) {
						$ioLatThres = $podConfig->ioLoadBalanceConfig->ioLatencyThreshold;
					}
					if($podConfig->ioLoadBalanceConfig->ioLoadImbalanceThreshold) {
						$ioLBThres = $podConfig->ioLoadBalanceConfig->ioLoadImbalanceThreshold;
					}
				}
				if($podConfig->loadBalanceInterval) {
					my $ioLBIntInMin = $podConfig->loadBalanceInterval;
					$ioLBInt = ($ioLBIntInMin / 60);
				}
				if(defined($podConfig->spaceLoadBalanceConfig)) {
					if($podConfig->spaceLoadBalanceConfig->minSpaceUtilizationDifference) {
						$minSpaceUtiDiff = $podConfig->spaceLoadBalanceConfig->minSpaceUtilizationDifference;
					}
					if($podConfig->spaceLoadBalanceConfig->spaceUtilizationThreshold) {
						$spaceUtilDiff = $podConfig->spaceLoadBalanceConfig->spaceUtilizationThreshold;
					}
				}
				if($podConfig->defaultIntraVmAffinity) {
					$defIntraVMAff = (($podConfig->defaultIntraVmAffinity) ? "YES" : "NO");
				}


				$datacenter_start .= "<tr><td>".$pod->name."</td><td>".(($podConfig->enabled) ? "YES" : "NO")."</td><td>".(($podConfig->ioLoadBalanceEnabled) ? "YES" : "NO")."</td><td>".$ioLatThres."ms</td><td>".$ioLBThres."</td><td>".$ioLBInt."hr</td><td>".$minSpaceUtiDiff."%</td><td>".$spaceUtilDiff."%</td><td>".$defIntraVMAff."</td><td>".$podConfig->defaultVmBehavior."</td></tr>";
			}
		}
		$datacenter_start .= "</table>\n";
	}

	##################
	# POD ADV OPTIONS
	##################
	if($DATASTORE_CLUSTER_POD_ADV_CONFIG eq "yes" && @$storagePods gt 0) {
		$hostTag = "Datastore Cluster Pod Advanced Configurations-$datacenter_name";
		$hostTagShort = "Datastore Cluster Pod Advanced Configurations";
		push @datastore_cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";
		$datacenter_start .= "<a name=\"$hostTag\"></a>\n";
		$datacenter_start .= "<h3>Datastore Cluster Pod Advanced Configurations:</h3>\n";
		$datacenter_start .= "<table border=\"1\">\n";
		$datacenter_start .= "<tr><th>STORAGE POD NAME</th><th>ADVANCED CONFIGURATIONS</th>\n";

		foreach my $pod (@$storagePods) {
			if(defined($pod->podStorageDrsEntry)) {
				my $podConfig = $pod->podStorageDrsEntry->storageDrsConfig->podConfig;
				if($podConfig->option) {
					my $podrules_string = "";
					my $podRules = $podConfig->option;
					foreach(@$podRules) {
						my $podkey = defined($_->key) ? $_->key : "N/A";
						my $podval = defined($_->value) ? $_->value : "N/A";
						$podrules_string .=  $podkey . " = " . $podval . "<br>";
					}
					$datacenter_start .= "<tr><td>" . $pod->name . "</td><td>" . $podrules_string . "</td></tr>\n";
				}
			}
		}
		$datacenter_start .= "</table>\n";
	}

	##################
	# POD STORAGE
	##################
	if($DATASTORE_CLUSTER_POD_STORAGE eq "yes" && @$storagePods gt 0) {
		$hostTag = "Datastore Cluster Pod Storage-$datacenter_name";
		$hostTagShort = "Datastore Cluster Pod Storage";
		push @datastore_cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";
		$datacenter_start .= "<a name=\"$hostTag\"></a>\n";
		$datacenter_start .= "<h3>Datastore Cluster Pod Storage:</h3>\n";
		$datacenter_start .= "<table border=\"1\">\n";
		$datacenter_start .= "<tr><th>STORAGE POD NAME</th><th>DATASTORES</th><th>MAINTENANCE MODE</th>\n";

		foreach my $pod (@$storagePods) {
			if(defined($pod->summary)) {
				my @podDatastores = ();
				my $podDSCount = 0;
				# If a pod has no datastores, childEntity will be undef, so force an empty array.
				foreach my $ds ( defined($pod->childEntity) ? @{$pod->childEntity} : () ) {
					my $child_view = Vim::get_view(mo_ref => $ds, properties => ['name','summary.maintenanceMode']);

					if($child_view->isa("Datastore")) {
						push @podDatastores, $child_view;
					}
				}

				my ($podDSString,$podDSMMString) = ("","");
				foreach(@podDatastores) {
					$podDSString .= $_->{'name'} . "<br>";
					$podDSMMString .= $_->{'summary.maintenanceMode'} . "<br>";
				}
				$datacenter_start .= "<tr><td>" . $pod->name . "</td><td>" . $podDSString . "</td><td>" . $podDSMMString . "</td></tr>\n";
			}
		}
		$datacenter_start .= "</table>\n";
	}

	##############
	# DVS SUMMARY
	##############
	if($DVS_SUMMARY eq "yes" && @$dvs gt 0) {
		$hostTag = "DVS Summary-$datacenter_name";
		$hostTagShort = "DVS Summary";
		push @datastore_cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";
		$datacenter_start .= "<a name=\"$hostTag\"></a>\n";
		$datacenter_start .= "<h3>DVS Summary:</h3>\n";
		$datacenter_start .= "<table border=\"1\">\n";
		$datacenter_start .= "<tr><th>DVS NAME</th><th># OF PORTS</th><th>VENDOR</th><th>VERSION</th><th>BUILD</th><th>UUID</th></tr>\n";

		foreach my $dvSwitch (@$dvs) {
			$datacenter_start .= "<tr>";
			$datacenter_start .= "<td>".$dvSwitch->summary->name."</td>";
			$datacenter_start .= "<td>".$dvSwitch->summary->numPorts."</td>";
			$datacenter_start .= "<td>".($dvSwitch->summary->productInfo->vendor ? $dvSwitch->summary->productInfo->vendor : "N/A")."</td>";
			$datacenter_start .= "<td>".($dvSwitch->summary->productInfo->version ? $dvSwitch->summary->productInfo->version : "N/A")."</td>";
			$datacenter_start .= "<td>".($dvSwitch->summary->productInfo->build ? $dvSwitch->summary->productInfo->build : "N/A")."</td>";
			$datacenter_start .= "<td>".$dvSwitch->summary->uuid."</td>";
			$datacenter_start .= "</tr>\n";
		}
		$datacenter_start .= "</table>\n";
	}
	#################
	# DVS CAPABILITY
	#################
	if($DVS_CAPABILITY && @$dvs gt 0) {
		$hostTag = "DVS Capability-$datacenter_name";
		$hostTagShort = "DVS Capability";
		push @datastore_cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";
		$datacenter_start .= "<a name=\"$hostTag\"></a>\n";
		$datacenter_start .= "<h3>DVS Capability:</h3>\n";
		$datacenter_start .= "<table border=\"1\">\n";
		$datacenter_start .= "<tr><th>DVS NAME</th><th>NIOC SUPPORT</th><th>QOS SUPPORT</th><th>DIRECT PATH GEN2 SUPPORT</th><th>DEFINE NETWORK RSC POOLS SUPPORT</th><th>NETWORK RSC POOL HIGH SHARE VAL</th><th>NIC TEAMING POLICY</th></tr>";

		my ($niocSup,$qosSup,$defNetRscPoolSup,$netRscPoolShareVal,$dp2Sup,$nicTeam) = ("N/A","N/A","N/A","N/A","N/A","N/A",);

		foreach my $dvSwitch (@$dvs) {
			if($dvSwitch->capability->featuresSupported) {
				my $dvFeatures = $dvSwitch->capability->featuresSupported;
				$niocSup = $dvFeatures->networkResourceManagementCapability->networkResourceManagementSupported ? "YES" : "NO";
				$qosSup = $dvFeatures->networkResourceManagementCapability->qosSupported ? "YES" : "NO";
				$defNetRscPoolSup = $dvFeatures->networkResourceManagementCapability->userDefinedNetworkResourcePoolsSupported ? "YES" : "NO";
				$netRscPoolShareVal = $dvFeatures->networkResourceManagementCapability->networkResourcePoolHighShareValue ? $dvFeatures->networkResourceManagementCapability->networkResourcePoolHighShareValue : "N/A";
				$dp2Sup = $dvFeatures->vmDirectPathGen2Supported ? "YES" : "NO";
				$nicTeam = $dvFeatures->nicTeamingPolicy ? join('<br>',@{$dvFeatures->nicTeamingPolicy}) : "N/A";
			}
			$datacenter_start .= "<tr>";
			$datacenter_start .= "<td>".$dvSwitch->summary->name."</td>";
			$datacenter_start .= "<td>".$niocSup."</td>";
			$datacenter_start .= "<td>".$qosSup."</td>";
			$datacenter_start .= "<td>".$dp2Sup."</td>";
			$datacenter_start .= "<td>".$defNetRscPoolSup."</td>";
			$datacenter_start .= "<td>".$netRscPoolShareVal."</td>";
			$datacenter_start .= "<td>".$nicTeam."</td>";
			$datacenter_start .= "</tr>\n";
		}
		$datacenter_start .= "</table>\n";
	}
	##############
	# DVS CONFIG
	##############
	if($DVS_CONFIG eq "yes" && @$dvs gt 0) {
		$hostTag = "DVS Config-$datacenter_name";
		$hostTagShort = "DVS Config";
		push @datastore_cluster_jump_tags,"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"#$hostTag\">$hostTagShort</a><br/>\n";
		$datacenter_start .= "<a name=\"$hostTag\"></a>\n";
		$datacenter_start .= "<h3>DVS Config:</h3>\n";
		$datacenter_start .= "<table border=\"1\">\n";
		$datacenter_start .= "<tr><th>DVS NAME</th><th>SWITCH ADDRESS</th><th>MAX PORTS</th><th>STANDALONE PORTS</th><th>MTU</th><th>NIOC ENABLED</th><th>LDP OPERATION</th><th>LDP PROTOCOL</th><th>ACTIVE FLOW TIMEOUT</th><th>IDLE FLOW TIMEOUT</th><th>INTERNAL FLOW ONLY</th><th>SAMPLE RATE</th><th>EXT KEY</th><th>CONFIG VERSION</th><th>DESCRIPTION</th><th>CREATE TIME</th></tr>\n";

		foreach my $dvSwitch (@$dvs) {
			my ($mtu,$ldpOp,$ldpPro,$activeFlowTimeout,$idleFlowTimeout,$intFlowOnly,$sampleRate) = ("N/A","N/A","N/A","N/A","N/A","N/A");
			if($dvSwitch->config->isa('VMwareDVSConfigInfo')) {
				$mtu = $dvSwitch->config->maxMtu;
				$ldpOp = $dvSwitch->config->linkDiscoveryProtocolConfig->operation ? $dvSwitch->config->linkDiscoveryProtocolConfig->operation : "N/A";
				$ldpPro = $dvSwitch->config->linkDiscoveryProtocolConfig->protocol ? $dvSwitch->config->linkDiscoveryProtocolConfig->protocol : "N/A";
				$activeFlowTimeout = $dvSwitch->config->ipfixConfig->activeFlowTimeout ? $dvSwitch->config->ipfixConfig->activeFlowTimeout : "N/A";
				$idleFlowTimeout = $dvSwitch->config->ipfixConfig->idleFlowTimeout ? $dvSwitch->config->ipfixConfig->idleFlowTimeout : "N/A";
				$intFlowOnly = $dvSwitch->config->ipfixConfig->internalFlowsOnly ? "YES" : "NO";
				$sampleRate = $dvSwitch->config->ipfixConfig->samplingRate ? $dvSwitch->config->ipfixConfig->samplingRate : "N/A";

			}

			$datacenter_start .= "<tr>";
			$datacenter_start .= "<td>".$dvSwitch->summary->name."</td>";
			$datacenter_start .= "<td>".($dvSwitch->config->switchIpAddress ? $dvSwitch->config->switchIpAddress : "N/A")."</td>";
			$datacenter_start .= "<td>".$dvSwitch->config->maxPorts."</td>";
			$datacenter_start .= "<td>".$dvSwitch->config->numStandalonePorts."</td>";
			$datacenter_start .= "<td>".$mtu."</td>";
			$datacenter_start .= "<td>".($dvSwitch->config->networkResourceManagementEnabled ? "YES" : "NO")."</td>";
			$datacenter_start .= "<td>".$ldpOp."</td>";
			$datacenter_start .= "<td>".$ldpPro."</td>";
			$datacenter_start .= "<td>".$activeFlowTimeout." sec</td>";
			$datacenter_start .= "<td>".$idleFlowTimeout." sec</td>";
			$datacenter_start .= "<td>".$intFlowOnly."</td>";
			$datacenter_start .= "<td>".$sampleRate."</td>";
			$datacenter_start .= "<td>".($dvSwitch->config->extensionKey ? $dvSwitch->config->extensionKey : "N/A")."</td>";
			$datacenter_start .= "<td>".$dvSwitch->config->configVersion."</td>";
			$datacenter_start .= "<td>".($dvSwitch->config->description ? $dvSwitch->config->description : "N/A")."</td>";
			$datacenter_start .= "<td>".$dvSwitch->config->createTime."</td>";
			$datacenter_start .= "</tr>\n";
		}
		$datacenter_start .= "</table>\n";
	}

	print REPORT_OUTPUT "<br/>".$datacenter_start;
}

sub processOptions {
	my ($type,$hostType,$conf) = @_;

	if(defined($conf)) {
		&processConf($conf);
		&setConf();
	}

	if($type eq 'host' && $hostType eq 'HostAgent') {
		$host_view = Vim::find_entity_views(view_type => 'HostSystem');
		unless($host_view) {
			Util::disconnect();
			die "ESX/ESXi host was not found\n";
		}
	}elsif($type eq 'cluster' && $hostType eq 'VirtualCenter') {
		$cluster_view = Vim::find_entity_view(view_type => 'ClusterComputeResource',filter => { name => $clusterInput });
		unless($cluster_view) {
			Util::disconnect();
			die "Error: Unable to find Cluster: \"$clusterInput\"!\n";
			exit 1;
		}
	}elsif($type eq 'datacenter' && $hostType eq 'VirtualCenter') {
		$datacenter_view = Vim::find_entity_view(view_type => 'Datacenter',filter => { name => $datacenterInput});
		unless($datacenter_view) {
			Util::disconnect();
			die "Error: Unable to find Datacenter: \"$datacenterInput\"!\n";
			exit 1;
		}
		my $CCR = Vim::find_entity_views(view_type => 'ClusterComputeResource', begin_entity => $datacenter_view);
		my $CR = Vim::find_entity_views(view_type => 'ComputeResource', begin_entity => $datacenter_view);
		my @list = (@$CCR,@$CR);
		my %seen = ();
		my @unique = grep { ! $seen{$_->name} ++ } @list;
		$cluster_views = \@unique;
	}elsif($type eq 'vcenter' && $hostType eq 'VirtualCenter') {
		my $CCR = Vim::find_entity_views(view_type => 'ClusterComputeResource');
		my $CR = Vim::find_entity_views(view_type => 'ComputeResource');
		my @list = (@$CCR,@$CR);
		my %seen = ();
		my @unique = grep { ! $seen{$_->name} ++ } @list;
		$cluster_views = \@unique;
	}
}

sub processConf {
	my ($conf) = @_;

	my @goodparams = qw(
EMAIL_HOST
EMAIL_DOMAIN
EMAIL_TO
EMAIL_FROM
YELLOW_WARN
ORANGE_WARN
RED_WARN
SNAPSHOT_YELLOW_WARN
SNAPSHOT_ORANGE_WARN
SNAPSHOT_RED_WARN
SYSTEM_LICENSE
SYSTEM_FEATURE
SYSTEM_PERMISSION
SYSTEM_SESSION
SYSTEM_HOST_PROFILE
SYSTEM_PLUGIN
DVS_SUMMARY
DVS_CAPABILITY
DVS_CONFIG
DATASTORE_CLUSTER_SUMMARY
DATASTORE_CLUSTER_POD_CONFIG
CLUSTER_SUMMARY
CLUSTER_PERFORMANCE
CLUSTER_HA
CLUSTER_DRS
CLUSTER_DPM
CLUSTER_AFFINITY
CLUSTER_GROUP
CLUSTER_RP
CLUSTER_VAPP
HOST_HARDWARE_CONFIGURATION
HOST_MGMT
HOST_STATE
HOST_HEALTH
HOST_PERFORMANCE
HOST_NIC
HOST_HBA
HOST_CAPABILITY
HOST_CONFIGURATION
HOST_VMOTION
HOST_GATEWAY
HOST_ISCSI
HOST_IPV6
HOST_FT
HOST_SSL
HOST_DNS
HOST_UPTIME
HOST_DIAGONISTIC
HOST_AUTH_SERVICE
HOST_SERVICE
HOST_NTP
HOST_VSWIF
HOST_VMKERNEL
HOST_VSWITCH
HOST_SNMP
HOST_FIREWALL
HOST_POWER
HOST_FEATURE_VERSION
HOST_ADVOPT
HOST_AGENT
HOST_NUMA
HOST_CDP
HOST_LUN
HOST_DATASTORE
HOST_CACHE
HOST_MULTIPATH
HOST_PORTGROUP
HOST_DVS
HOST_LOG
HOST_TASK
VM_STATE
VM_CONFIG
VM_STATS
VM_RESOURCE_ALLOCATION
VM_PERFORMANCE
VM_FT
VM_EZT
VM_THIN
VM_DEVICE
VM_STORAGE
VM_NETWORK
VM_SNAPSHOT
VM_DELTA
VM_CDROM
VM_FLOPPY
VM_RDM
VM_NPIV
VM_TOOL
VPX_SETTING
VMW_APP
);

	open(CONFIG, "$conf") || die "Error: Couldn't open the $conf!";
	while (<CONFIG>) {
		chomp;
		s/#.*//; # Remove comments
		s/^\s+//; # Remove opening whitespace
		s/\s+$//;  # Remove closing whitespace
		next unless length;
		my ($key, $value) = split(/\s*=\s*/, $_, 2);
		if( grep $key eq $_,  @goodparams ) {
			$value =~ s/"//g;
			if($key eq "EMAIL_TO") {
				@EMAIL_TO = ();
				@EMAIL_TO = split(',',$value);
			} else {
				$configurations{$key} = $value;
			}
		}
	}
	close(CONFIG);
}

sub processAdditionalConf {
	if($hostlist) {
		&processSubFiles($hostlist);
	}
	if($vmlist) {
		&processSubFiles($vmlist);
	}
}

sub processSubFiles {
	my ($config_input) = @_;

	open(CONFIG, "$config_input") || die "Error: Couldn't open the $config_input!";
	while (<CONFIG>) {
		chomp;
		s/#.*//; # Remove comments
		s/^\s+//; # Remove opening whitespace
		s/\s+$//;  # Remove closing whitespace
		next unless length;
		if($hostlist) {
			$hostlists{$_} = "yes";
		}
		if($vmlist) {
			$vmlists{$_} = "yes";
		}
	}
	close(CONFIG);
}

sub setConf {
	$EMAIL_HOST=(($configurations{'EMAIL_HOST'}) ? $configurations{'EMAIL_HOST'} : 'emailserver');
	$EMAIL_DOMAIN=(($configurations{'EMAIL_DOMAIN'}) ? $configurations{'EMAIL_DOMAIN'} : 'localhost.localdomain');
	#@EMAIL_TO=(($configurations{'EMAIL_TO'}) ? $configurations{'EMAIL_TO'} : 'william@primp-industries.com.com');
	$EMAIL_FROM=(($configurations{'EMAIL_FROM'}) ? $configurations{'EMAIL_FROM'} : 'vMA@primp-industries.com.com');
	$YELLOW_WARN=(($configurations{'YELLOW_WARN'}) ? $configurations{'YELLOW_WARN'} : 30);
	$ORANGE_WARN=(($configurations{'ORANGE_WARN'}) ? $configurations{'ORANGE_WARN'} : 15);
	$RED_WARN=(($configurations{'RED_WARN'}) ? $configurations{'RED_WARN'} : 10);
	$SNAPSHOT_YELLOW_WARN=(($configurations{'SNAPSHOT_YELLOW_WARN'}) ? $configurations{'SNAPSHOT_YELLOW_WARN'} : 15);
	$SNAPSHOT_ORANGE_WARN=(($configurations{'SNAPSHOT_ORANGE_WARN'}) ? $configurations{'SNAPSHOT_ORANGE_WARN'} : 30);
	$SNAPSHOT_RED_WARN=(($configurations{'SNAPSHOT_RED_WARN'}) ? $configurations{'SNAPSHOT_RED_WARN'} : 60);
	$SYSTEM_LICENSE=(($configurations{'SYSTEM_LICENSE'}) ? $configurations{'SYSTEM_LICENSE'} : "yes");
	$SYSTEM_FEATURE=(($configurations{'SYSTEM_FEATURE'}) ? $configurations{'SYSTEM_FEATURE'} : "yes");
	$SYSTEM_PERMISSION=(($configurations{'SYSTEM_PERMISSION'}) ? $configurations{'SYSTEM_PERMISSION'} : "yes");
	$SYSTEM_SESSION=(($configurations{'SYSTEM_SESSION'}) ? $configurations{'SYSTEM_SESSION'} : "yes");
	$SYSTEM_HOST_PROFILE=(($configurations{'SYSTEM_HOST_PROFILE'}) ? $configurations{'SYSTEM_HOST_PROFILE'} : "yes");
	$SYSTEM_PLUGIN=(($configurations{'SYSTEM_PLUGIN'}) ? $configurations{'SYSTEM_PLUGIN'} : "yes");
	$DVS_SUMMARY=(($configurations{'DVS_SUMMARY'}) ? $configurations{'DVS_SUMMARY'} : "yes");
	$DVS_CAPABILITY=(($configurations{'DVS_CAPABILITY'}) ? $configurations{'DVS_CAPABILITY'} : "yes");
	$DVS_CONFIG=(($configurations{'DVS_CONFIG'}) ? $configurations{'DVS_CONFIG'} : "yes");
	$DATASTORE_CLUSTER_SUMMARY=(($configurations{'DATASTORE_CLUSTER_SUMMARY'}) ? $configurations{'DATASTORE_CLUSTER_SUMMARY'} : "yes");
	$DATASTORE_CLUSTER_POD_CONFIG=(($configurations{'DATASTORE_CLUSTER_POD_CONFIG'}) ? $configurations{'DATASTORE_CLUSTER_POD_CONFIG'} : "yes");
	$DATASTORE_CLUSTER_POD_ADV_CONFIG=(($configurations{'DATASTORE_CLUSTER_POD_ADV_CONFIG'}) ? $configurations{'DATASTORE_CLUSTER_POD_ADV_CONFIG'} : "yes");
	$DATASTORE_CLUSTER_POD_STORAGE=(($configurations{'DATASTORE_CLUSTER_POD_STORAGE'}) ? $configurations{'DATASTORE_CLUSTER_POD_STORAGE'} : "yes");
	$CLUSTER_SUMMARY=(($configurations{'CLUSTER_SUMMARY'}) ? $configurations{'CLUSTER_SUMMARY'} : "yes");
	$CLUSTER_PERFORMANCE=(($configurations{'CLUSTER_PERFORMANCE'}) ? $configurations{'CLUSTER_PERFORMANCE'} : "yes");
	$CLUSTER_HA=(($configurations{'CLUSTER_HA'}) ? $configurations{'CLUSTER_HA'} : "yes");
	$CLUSTER_DRS=(($configurations{'CLUSTER_DRS'}) ? $configurations{'CLUSTER_DRS'} : "yes");
	$CLUSTER_DPM=(($configurations{'CLUSTER_DPM'}) ? $configurations{'CLUSTER_DPM'} : "yes");
	$CLUSTER_AFFINITY=(($configurations{'CLUSTER_AFFINITY'}) ? $configurations{'CLUSTER_AFFINITY'} : "yes");
	$CLUSTER_GROUP=(($configurations{'CLUSTER_GROUP'}) ? $configurations{'CLUSTER_GROUP'} : "yes");
	$CLUSTER_RP=(($configurations{'CLUSTER_RP'}) ? $configurations{'CLUSTER_RP'} : "yes");
	$CLUSTER_VAPP=(($configurations{'CLUSTER_VAPP'}) ? $configurations{'CLUSTER_VAPP'} : "yes");
	$HOST_HARDWARE_CONFIGURATION=(($configurations{'HOST_HARDWARE_CONFIGURATION'}) ? $configurations{'HOST_HARDWARE_CONFIGURATION'} : "yes");
	$HOST_MGMT=(($configurations{'HOST_MGMT'}) ? $configurations{'HOST_MGMT'} : "yes");
	$HOST_STATE=(($configurations{'HOST_STATE'}) ? $configurations{'HOST_STATE'} : "yes");
	$HOST_HEALTH=(($configurations{'HOST_HEALTH'}) ? $configurations{'HOST_HEALTH'} : "yes");
	$HOST_PERFORMANCE=(($configurations{'HOST_PERFORMANCE'}) ? $configurations{'HOST_PERFORMANCE'} : "yes");
	$HOST_NIC=(($configurations{'HOST_NIC'}) ? $configurations{'HOST_NIC'} : "yes");
	$HOST_HBA=(($configurations{'HOST_HBA'} ? $configurations{'HOST_HBA'} : "yes"));
	$HOST_CAPABILITY=(($configurations{'HOST_CAPABILITY'} ? $configurations{'HOST_CAPABILITY'} : "yes"));
	$HOST_CONFIGURATION=(($configurations{'HOST_CONFIGURATION'}) ? $configurations{'HOST_CONFIGURATION'} : "yes");
	$HOST_VMOTION=(($configurations{'HOST_VMOTION'}) ? $configurations{'HOST_VMOTION'} : "yes");
	$HOST_GATEWAY=(($configurations{'HOST_GATEWAY'}) ? $configurations{'HOST_GATEWAY'} : "yes");
	$HOST_ISCSI=(($configurations{'HOST_ISCSI'}) ? $configurations{'HOST_ISCSI'} : "yes");
	$HOST_IPV6=(($configurations{'HOST_IPV6'}) ? $configurations{'HOST_IPV6'} : "yes");
	$HOST_FT=(($configurations{'HOST_FT'}) ? $configurations{'HOST_FT'} : "yes");
	$HOST_SSL=(($configurations{'HOST_SSL'}) ? $configurations{'HOST_SSL'} : "yes");
	$HOST_DNS=(($configurations{'HOST_DNS'}) ? $configurations{'HOST_DNS'} : "yes");
	$HOST_UPTIME=(($configurations{'HOST_UPTIME'}) ? $configurations{'HOST_UPTIME'} : "yes");
	$HOST_DIAGONISTIC=(($configurations{'HOST_DIAGONISTIC'}) ? $configurations{'HOST_DIAGONISTIC'} : "yes");
	$HOST_AUTH_SERVICE=(($configurations{'HOST_AUTH_SERVICE'}) ? $configurations{'HOST_AUTH_SERVICE'} : "yes");
	$HOST_SERVICE=(($configurations{'HOST_SERVICE'}) ? $configurations{'HOST_SERVICE'} : "yes");
	$HOST_NTP=(($configurations{'HOST_NTP'}) ? $configurations{'HOST_NTP'} : "yes");
	$HOST_VSWIF=(($configurations{'HOST_VSWIF'}) ? $configurations{'HOST_VSWIF'} : "yes");
	$HOST_VMKERNEL=(($configurations{'HOST_VMKERNEL'}) ? $configurations{'HOST_VMKERNEL'} : "yes");
	$HOST_VSWITCH=(($configurations{'HOST_VSWITCH'}) ? $configurations{'HOST_VSWITCH'} : "yes");
	$HOST_SNMP=(($configurations{'HOST_SNMP'}) ? $configurations{'HOST_SNMP'} : "yes");
	$HOST_FIREWALL=(($configurations{'HOST_FIREWALL'}) ? $configurations{'HOST_FIREWALL'} : "yes");
	$HOST_POWER=(($configurations{'HOST_POWER'}) ? $configurations{'HOST_POWER'} : "yes");
	$HOST_FEATURE_VERSION=(($configurations{'HOST_FEATURE_VERSION'}) ? $configurations{'HOST_FEATURE_VERSION'} : "yes");
	$HOST_ADVOPT=(($configurations{'HOST_ADVOPT'}) ? $configurations{'HOST_ADVOPT'} : "yes");
	$HOST_AGENT=(($configurations{'HOST_AGENT'}) ? $configurations{'HOST_AGENT'} : "yes");
	$HOST_NUMA=(($configurations{'HOST_NUMA'}) ? $configurations{'HOST_NUMA'} : "yes");
	$HOST_CDP=(($configurations{'HOST_CDP'}) ? $configurations{'HOST_CDP'} : "yes");
	$HOST_LUN=(($configurations{'HOST_LUN'}) ? $configurations{'HOST_LUN'} : "yes");
	$HOST_DATASTORE=(($configurations{'HOST_DATASTORE'}) ? $configurations{'HOST_DATASTORE'} : "yes");
	$HOST_CACHE=(($configurations{'HOST_CACHE'}) ? $configurations{'HOST_CACHE'} : "yes");
	$HOST_MULTIPATH=(($configurations{'HOST_MULTIPATH'}) ? $configurations{'HOST_MULTIPATH'} : "yes");
	$HOST_PORTGROUP=(($configurations{'HOST_PORTGROUP'}) ? $configurations{'HOST_PORTGROUP'} : "yes");
	$HOST_DVS=(($configurations{'HOST_DVS'}) ? $configurations{'HOST_DVS'} : "yes");
	$HOST_LOG=(($configurations{'HOST_LOG'}) ? $configurations{'HOST_LOG'} : "yes");
	$HOST_TASK=(($configurations{'HOST_TASK'}) ? $configurations{'HOST_TASK'} : "yes");
	$VM_STATE=(($configurations{'VM_STATE'}) ? $configurations{'VM_STATE'} : "yes");
	$VM_CONFIG=(($configurations{'VM_CONFIG'}) ? $configurations{'VM_CONFIG'} : "yes");
	$VM_STATS=(($configurations{'VM_STATS'}) ? $configurations{'VM_STATS'} : "yes");
	$VM_RESOURCE_ALLOCATION=(($configurations{'VM_RESOURCE_ALLOCATION'}) ? $configurations{'VM_RESOURCE_ALLOCATION'} : "yes");
	$VM_PERFORMANCE=(($configurations{'VM_PERFORMANCE'}) ? $configurations{'VM_PERFORMANCE'} : "yes");
	$VM_FT=(($configurations{'VM_FT'}) ? $configurations{'VM_FT'} : "yes");
	$VM_EZT=(($configurations{'VM_EZT'}) ? $configurations{'VM_EZT'} : "yes");
	$VM_THIN=(($configurations{'VM_THIN'}) ? $configurations{'VM_THIN'} : "yes");
	$VM_DEVICE=(($configurations{'VM_DEVICE'}) ? $configurations{'VM_DEVICE'} : "yes");
	$VM_STORAGE=(($configurations{'VM_STORAGE'}) ? $configurations{'VM_STORAGE'} : "yes");
	$VM_NETWORK=(($configurations{'VM_NETWORK'}) ? $configurations{'VM_NETWORK'} : "yes");
	$VM_SNAPSHOT=(($configurations{'VM_SNAPSHOT'}) ? $configurations{'VM_SNAPSHOT'} : "yes");
	$VM_DELTA=(($configurations{'VM_DELTA'}) ? $configurations{'VM_DELTA'} : "yes");
	$VM_CDROM=(($configurations{'VM_CDROM'}) ? $configurations{'VM_CDROM'} : "yes");
	$VM_FLOPPY=(($configurations{'VM_FLOPPY'}) ? $configurations{'VM_FLOPPY'} : "yes");
	$VM_RDM=(($configurations{'VM_RDM'}) ? $configurations{'VM_RDM'} : "yes");
	$VM_NPIV=(($configurations{'VM_NPIV'}) ? $configurations{'VM_NPIV'} : "yes");
	$VM_TOOL=(($configurations{'VM_TOOL'}) ? $configurations{'VM_TOOL'} : "yes");
	$VMW_APP=(($configurations{'VMW_APP'}) ? $configurations{'VMW_APP'} : "yes");
	$VPX_SETTING=(($configurations{'VPX_SETTING'}) ? $configurations{'VPX_SETTING'} : "yes");
}

sub getCpuAndMemPerf {
	my ($entity_view) = @_;
	my $returnString = "";

	my @metrics;
	my %metricResults = ();

	if($entity_view->isa('ClusterComputeResource')) {
		@metrics = qw(cpu.usage.average cpu.usagemhz.average mem.consumed.average mem.active.average);
	}elsif($entity_view->isa('HostSystem')) {
		@metrics = qw(cpu.usage.average cpu.usagemhz.average mem.usage.average mem.active.average);
	}elsif($entity_view->isa('VirtualMachine')) {
		@metrics = qw(cpu.usage.average cpu.usagemhz.average mem.usage.average mem.active.average cpu.ready.summation cpu.vmmemctl.average);
	}

	my $entity_name = $entity_view->name;

	#get performance manager
	my $perfMgr = Vim::get_view(mo_ref => $service_content->perfManager);

	#get performance counters
	my $perfCounterInfo = $perfMgr->perfCounter;

	#grab all counter defs
	my %allCounterDefintions = ();
	foreach(@$perfCounterInfo) {
		$allCounterDefintions{$_->key} = $_;
	}

	my @metricIDs = ();

	#get available metrics from entity
	my $availmetricid = $perfMgr->QueryAvailablePerfMetric(entity => $entity_view);

	foreach(sort {$a->counterId cmp $b->counterId} @$availmetricid) {
		if($allCounterDefintions{$_->counterId}) {
			my $metric = $allCounterDefintions{$_->counterId};
			my $groupInfo = $metric->groupInfo->key;
			my $nameInfo = $metric->nameInfo->key;
			my $instance = $_->instance;
			my $key = $metric->key;
			my $rolluptype = $metric->rollupType->val;
			my $statstype = $metric->statsType->val;
			my $unitInfo = $metric->unitInfo->key;

			#e.g. cpu.usage.average
			my $vmwInternalName = $groupInfo . "." . $nameInfo . "." . $rolluptype;

			foreach(@metrics) {
				if($_ eq $vmwInternalName) {
					#print $groupInfo . "\t" . $nameInfo . "\t" . $rolluptype . "\t" . $statstype . "\t" . $unitInfo . "\n";
					my $metricId = PerfMetricId->new(counterId => $key, instance => '*');
					if(! grep(/^$key/,@metricIDs)) {
						push @metricIDs,$metricId;
					}
				}
			}
		}
	}
	my $intervalIds = &get_available_intervals(perfmgr_view => $perfMgr, entity => $entity_view);

	my $perfQuerySpec = PerfQuerySpec->new(entity => $entity_view, maxSample => 10, intervalId => shift(@$intervalIds), metricId => \@metricIDs);

	my $metrics;
	eval {
		$metrics = $perfMgr->QueryPerf(querySpec => [$perfQuerySpec]);
	};
	if(!$@) {
		my %uniqueInstances = ();
		foreach(@$metrics) {
			my $perfValues = $_->value;
			foreach(@$perfValues) {
				my $object = $_->id->instance ? $_->id->instance : "TOTAL";
				#if($object eq "TOTAL") {
					my ($numOfCounters,$sumOfCounters,$res) = (0,0,0);
					my $values = $_->value;
					my $metricRef = $allCounterDefintions{$_->id->counterId};
					my $unitString = $metricRef->unitInfo->label;
					my $unitInfo = $metricRef->unitInfo->key;
					my $groupInfo = $metricRef->groupInfo->key;
					my $nameInfo = $metricRef->nameInfo->key;
					my $rollupType = $metricRef->rollupType->val;
					my $factor = 1;
					if($unitInfo eq 'percent') { $factor = 100; }

					foreach(@$values) {
						#if($rollupType eq 'average') {
							$res = &average($_)/$factor;
							$res = &restrict_num_decimal_digits($res,3);
						#}
					}
					my $internalID = $groupInfo . "." . $nameInfo . "." . $rollupType;
					$metricResults{$internalID} = $res . "\t" . $unitString . "\n";
				#}
			}
		}
	}

	my ($cpuAvg,$cpuAvgPer,$memAvg,$memAvgPer,$ballonAvg,$readyAvg) = (0,0,0,0,0,0);

	for my $key ( sort keys %metricResults ) {
		if($key eq 'cpu.usage.average') {
			$cpuAvgPer = $metricResults{$key};
		}elsif($key eq 'cpu.usagemhz.average') {
			$cpuAvg = $metricResults{$key};
		}elsif($key eq 'mem.usage.average' || $key eq 'mem.consumed.average') {
			if($entity_view->isa('ClusterComputeResource') && $key eq 'mem.consumed.average') {
				$memAvgPer = $metricResults{$key};
			}elsif(!$entity_view->isa('ClusterComputeResource') && $key eq 'mem.usage.average'){
				$memAvgPer = $metricResults{$key};
			}
		}elsif($key eq 'mem.active.average') {
			$memAvg = $metricResults{$key};
		}elsif($key eq 'cpu.ready.summation') {
			$readyAvg = $metricResults{$key};
		}elsif($key eq 'cpu.vmmemctl.average') {
			$ballonAvg = $metricResults{$key};
		}
	}

	my ($perfString,$hostTag,$hostTagShort) = ("","","");

	if($entity_view->isa('ClusterComputeResource')) {
		$perfString .= "<h3>Cluster Performance</h3>\n";
		$perfString .= "<table border=\"1\">\n";
		$perfString .= "<tr><th>cpu.usagemhz.average</th><th>cpu.usage.average</th><th>mem.active.average</th><th>mem.consumed.average</th></tr>\n";

		$perfString .= "<td>" . $cpuAvg . "</td>\n";
		$perfString .= "<td>" . $cpuAvgPer . "</td>\n";
		$perfString .= "<td>" . $memAvg . "</td>\n";
		$perfString .= "<td>" . $memAvgPer . "</td>\n";
		$perfString .= "</table>\n";
	} elsif($entity_view->isa('HostSystem')) {
		my $hostsystem_name = $entity_view->name;
		if($demo eq "yes") { $hostsystem_name = $host_name; }
		$perfString .= "<tr><td>" . $hostsystem_name . "</td><td>" . $cpuAvg . "</td><td>" . $cpuAvgPer . "</td><td>" . $memAvg . "</td><td>" . $memAvgPer . "</tr>\n";
	} else {
		$perfString .= "<tr><td>" . $entity_view->name . "</td><td>" . $cpuAvg . "</td><td>" . $cpuAvgPer . "</td><td>" . $readyAvg . "</td><td>" . $memAvg . "</td><td>" . $memAvgPer . "</td><td>" . $ballonAvg . "</tr>\n";
	}
	return $perfString;
}

#VMware's viperformance.pl function
sub get_available_intervals {
   my %args = @_;
   my $perfmgr_view = $args{perfmgr_view};
   my $entity = $args{entity};

   my $historical_intervals = $perfmgr_view->historicalInterval;
   my $provider_summary = $perfmgr_view->QueryPerfProviderSummary(entity => $entity);
   my @intervals;
   if ($provider_summary->refreshRate) {
      if($provider_summary->refreshRate != -1) {
	push @intervals, $provider_summary->refreshRate;
      }
   }
   foreach (@$historical_intervals) {
      if($_->samplingPeriod != -1) {
	push @intervals, $_->samplingPeriod;
      }
   }
   return \@intervals;
}

sub average {
   my @arr = @_;
   my $n = 0;
   my $avg = 0;

   foreach(@arr) {
	$avg += $_;
	$n += 1;
   }
   return $avg ? $avg/$n : 0;
}

sub FindPortGroupbyKey {
   my ($network, $vSwitch, $key) = @_;
   my $portGroups = $network->networkInfo->portgroup;
   foreach my $pg (@$portGroups) {
      return $pg if (($pg->vswitch eq $vSwitch) && ($key eq $pg->key));
   }
   return undef;
}

sub find_by_key {
   my ($list, $key) = @_;

   foreach my $item (@$list) {
      if ($key eq $item->key) {
	 return $item;
      }
   }

   return undef;
}

sub get_pci_string {
   my $hba = shift;
   my $pciString = defined($hba) ? $hba->pci : "";
   # defect 173631
   if ($pciString =~ /([a-fA-F0-9]+):([a-fA-F0-9]+)\.([a-fA-F0-9]+)$/) {
      $pciString = hexstr_to_int($1)
		   . ":" . hexstr_to_int($2)
		   . "." . hexstr_to_int($3);
   }
   return $pciString
}

sub hexstr_to_int {
    my ($hexstr) = @_;
    die "Invalid hex string: $hexstr"
    if $hexstr !~ /^[0-9A-Fa-f]{1,8}$/;
    my $num = hex($hexstr);
    return $num >> 31 ? $num - 2 ** 32 : $num;
}

sub getSnapshotTree {
	my ($host,$vm,$ref,$tree) = @_;

	my $head = " ";
	foreach my $node (@$tree) {
		$head = ($ref->value eq $node->snapshot->value) ? " " : " " if (defined $ref);
		my $quiesced = ($node->quiesced) ? "YES" : "NO";
		my $desc = $node->description;
		if($desc eq "" ) { $desc = "NO DESCRIPTION"; }
		push @vmsnapshots,"<td>".$host."</td><td>".$vm."</td><td>".$node->name."</td><td>".$desc."</td><td>".$node->createTime."</td><td>".$node->state->val."</td><td>".$quiesced."</td>";

		&getSnapshotTree($host, $vm, $ref, $node->childSnapshotList);
	}
	return;
}

sub startReport {
	print "Generating VMware vSphere Health Report v$version \"$report\" ...\n\n";
	print "This can take a few minutes depending on the size of your environment. \nGet a cup of coffee/tea/beer and check out http://www.virtuallyghetto.com\n\n";

	if($demo eq "yes") {
		$host_name = "DEMO-HOST.primp-industries.com";
	}

	$start_time = time();
	open(REPORT_OUTPUT, ">encoding(UTF-8)", "$report") or die $!;

	$my_time = "Date: ".giveMeDate('MDYHMS');
	my $html_start = <<HTML_START;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta name="author" content="William Lam"/>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<title>VMware vSphere Health Check Report v$version - $my_time ($system_name)</title>
<style type="text/css">
<!--
body {
	background: rgb(47,109,161);
	margin: 0;
	padding: 0;
	font: 10px normal Verdana, Arial, Helvetica, sans-serif;
	color: #444;
}
a:link { color: blue; }
a:visited { color: blue; }
a:hover { color: blue; }
a:active { color: blue; }
.author a:link { color: white; }
.author a:visited { color: white; }
.author a:hover { color: blue; }
.author a:active { color: white; }
th { font-weight:white; background-color:#CCCCCC; }
h1 {
	font-size: 3em;
	margin: 20px 0;
	color: white;
}
div.tabcontainer {
	width: 95%;
	height: 100%;
	margin: 10px auto;
}
ul.tabnav {
	list-style-type: none;
	margin: 0;
	padding: 0;
	width: 100%;
	overflow: hidden;
	border-top: none;
	clear: both;
	float: left;
	width: 100%;
	-moz-border-radius-bottomright: 5px;
	-khtml-border-radius-bottomright: 5px;
	-webkit-border-bottom-right-radius: 5px;
	-moz-border-radius-bottomleft: 5px;
	-khtml-border-radius-bottomleft: 5px;
	-webkit-border-bottom-left-radius: 5px;
}

ul.tabnav li {
	float: left;
	margin: 0;
	padding: 0;
	height: 31px;
	line-height: 31px;
	border: 1px solid #999;
	border-left: none;
	margin-bottom: -1px;
	overflow: hidden;
	position: relative;
	background: #ccc;
	font-weight: bold;
}
ul.tabnav li a {
	text-decoration: none;
	color: #000;
	display: block;
	font-size: 1.2em;
	padding: 0 20px;
	border: 1px solid #fff;
	outline: none;
}

ul.tabnav a:hover {
	background: #3E86BE;
}

div.tabcontents {
HTML_START

if($printerfriendly eq "no") {
	$html_start .= <<HTML_START;
	height: 550px;
HTML_START
}

$html_start .= <<HTML_START;
	background: #fff;
	overflow: hidden;
	border-top: 1px solid #011;
	padding: 20px;
	padding-bottom:30px;
}

div.tabcontents {
	float: left;
	width: 95%;
	overflow-y: hidden;
	padding: 20px;
	font-size: 1.2em;
}

div.content {
	float: left;
	width: 100%;
	height: 100%;
	overflow: -moz-scrollbars-vertical;
	overflow: auto;
	padding: 20px;
}

div.tabcontents div.content h2 {
	margin-top: 3px;
	font-weight: normal;
	padding-bottom: 10px;
	border-bottom: 1px dashed #ddd;
	font-size: 1.8em;
}
.author {
	font-weight: bold;
	font-size: small;
	clear: both;
	display: block;
	padding: 10px 0;
	text-align:center;
	color:white;
}
//-->
</style>

<script language="JavaScript">
visibleDiv = "";
function showHide(elementid,qstring){
  if (document.getElementById(elementid).style.display == 'none'){
    document.getElementById(elementid).style.display = '';
    if(visibleDiv != ""){
      if(visibleDiv != elementid){
	document.getElementById(visibleDiv).style.display = 'none';
      }
    }
    visibleDiv = elementid;
  } else {
    document.getElementById(elementid).style.display = 'none';
  }
}
</script>

</head>

HTML_START

	print REPORT_OUTPUT $html_start;
}

sub endReport {
	my $html_end = <<HTML_END;
<div class="author"><span class="author"Author: <b><a href="http://www.linkedin.com/in/lamwilliam">William Lam</a></b><br/>
<a href="http://www.virtuallyghetto.com">http://www.virtuallyghetto.com</a><br/>
Generated using: <b><a href="http://communities.vmware.com/docs/DOC-9842">vmwarevSphereHealthCheck.pl</a></b><br/>
Support us by donating <b><a href="http://www.virtuallyghetto.com/p/how-you-can-help.html">here</a></b><br/>
Primp Industries&#0153;
</span>
</div>
</html>
HTML_END

	print REPORT_OUTPUT $html_end;
	close(REPORT_OUTPUT);

	my @lines;
	my ($datastore_cluster_jump_string,$cluster_jump_string,$host_jump_string,$vm_jump_string) = ("","","","");
	tie @lines, 'Tie::File', $report or die;
	for(@lines) {
		if (/<!-- insert cluster jump -->/) {
			foreach (@cluster_jump_tags) {
				if( ($_ =~ /^CL/) ) {
					my $tmp_cluster_string = substr($_,2);
					$cluster_jump_string .= $tmp_cluster_string;
				}
				else {
					$cluster_jump_string .= $_;
				}
			}
			$_ = "\n$cluster_jump_string";
			last;
		}
	}
	for(@lines) {
		if (/<!-- insert datastore cluster jump -->/) {
			foreach (@datastore_cluster_jump_tags) {
				if( ($_ =~ /^CL/) ) {
					my $tmp_datastore_cluster_string = substr($_,2);
					$datastore_cluster_jump_string .= $tmp_datastore_cluster_string;
				}
				else {
					$datastore_cluster_jump_string .= $_;
				}
			}
			$_ = "\n$datastore_cluster_jump_string";
			last;
		}
	}
	for(@lines) {
		if (/<!-- insert host jump -->/) {
			foreach (@host_jump_tags) {
				if( ($_ =~ /^CL/) ) {
					my $tmp_host_string = substr($_,2);
					$host_jump_string .= $tmp_host_string;
				}
				else {
					$host_jump_string .= $_;
				}
			}
			$_ = "\n$host_jump_string";
			last;
		}
	}
	for(@lines) {
		if (/<!-- insert vm jump -->/) {
			foreach (@vm_jump_tags) {
				if( ($_ =~ /^CL/) ) {
					my $tmp_host_string = substr($_,2);
					$vm_jump_string .= $tmp_host_string;
				}
				else {
					$vm_jump_string .= $_;
				}
			}
			$_ = "\n$vm_jump_string";
			last;
		}
	}

	untie @lines;


	my $end_time = time();
	my $run_time = $end_time - $start_time;
	print "\nStart Time: ",&formatTime(str => scalar localtime($start_time)),"\n";
	print "End   Time: ",&formatTime(str => scalar localtime($end_time)),"\n";

	if ($run_time < 60) {
		print "Duration  : ",$run_time," Seconds\n\n";
	}
	else {
		print "Duration  : ",&restrict_num_decimal_digits($run_time/60,2)," Minutes\n\n";
	}
}

sub startBody {
	my ($type,$aversion) = @_;

	my $body_start = <<BODY_START;

<body>

<div class="tabcontainer">
	<h1>VMware vSphere Health Check Report v$version</h1>
	<ul class="tabnav">
		<li><a href="#tab1">System Summary</a></li>
BODY_START
		if($type eq 'VirtualCenter' && $VPX_SETTING eq "yes") {
			$body_start .= <<BODY_START;
		<li><a href="#tab5">vCenter Settings</a></li>
BODY_START
		}
		if($type eq 'VirtualCenter' && $VMW_APP eq "yes") {
			$body_start .= <<BODY_START;
		<li><a href="#tab6">VMware/3rd Party Applications</a></li>
BODY_START
		}
		if($type eq 'VirtualCenter' && ($aversion eq '5.0.0' || $aversion eq '5.1.0' || $aversion eq '5.5.0' || $aversion eq '6.0.0' || $aversion eq '6.5.0')) {
			$body_start .= <<BODY_START;
		<li><a href="#tab7">Datacenter</a></li>
BODY_START
		}
		if($type eq 'VirtualCenter') {
			$body_start .= <<BODY_START;
		<li><a href="#tab2">Cluster</a></li>
BODY_START
		}
		$body_start .= <<BODY_START;
		<li><a href="#tab3">Hosts</a></li>
		<li><a href="#tab4">Virtual Machines</a></li>
	</ul>
	<div class="tabcontents">
BODY_START

	print REPORT_OUTPUT $body_start;
}

sub endBody {
	my $body_end = <<BODY_END;

	</div>
</div>
</body>
BODY_END

	print REPORT_OUTPUT $body_end;
}

sub validateSystem {
	my ($ver) = @_;

	if(!grep(/$ver/,@supportedVersion)) {
		Util::disconnect();
		print "Error: This script only supports vSphere \"@supportedVersion\"! (found $ver)\n\n";
		exit 1;
	}
}

# restrict the number of digits after the decimal point
#http://guymal.com/mycode/perl_restrict_digits.shtml
sub restrict_num_decimal_digits {
	my $num=shift;#the number to work on
	my $digs_to_cut=shift;# the number of digits after

	if ($num=~/\d+\.(\d){$digs_to_cut,}/) {
		$num=sprintf("%.".($digs_to_cut-1)."f", $num);
	}
	return $num;
}

#http://www.infocopter.com/perl/format-time.html
sub formatTime(%) {
	my %args = @_;
	$args{'str'} ||= ''; # e.g. Mon Jul 3 12:59:28 2006

	my @elems = ();
	foreach (split / /, $args{'str'}) {
		next unless $_;
		push(@elems, $_);
	}

	my ($weekday, $month, $mday, $time, $yyyy) = split / /, join(' ', @elems);

	my %months = (  Jan => 1, Feb => 2, Mar => 3, Apr =>  4, May =>  5, Jun =>  6,
			Jul => 7, Aug => 8, Sep => 9, Oct => 10, Nov => 11, Dec => 12 );

	my $s  = substr($time, 6,2);
	my $m  = substr($time, 3,2);
	my $h  = substr($time, 0, 2);
	my $dd = sprintf('%02d', $mday);

	my $mm_num = sprintf('%02d', $months{$month});

	my $formatted = "$mm_num\-$dd\-$yyyy $h:$m:$s";
	#my $formatted = "$yyyy$mm_num$dd$h$m$s";

	$formatted;
}

#http://www.bryantmcgill.com/Shazam_Perl_Module/Subroutines/utils_convert_bytes_to_optimal_unit.html
sub prettyPrintData{
	my($bytes,$type) = @_;

	return '' if ($bytes eq '' || $type eq '');
	return 0 if ($bytes <= 0);

	my($size);

	if(grep (/^$type$/, ('B', 'K', 'M', 'G'))) {
		$bytes *= 1024 if ($type eq 'K');
		$bytes *= 1048576 if ($type eq 'M');
		$bytes *= 1073741824 if ($type eq 'G');

		$size = $bytes . ' Bytes' if ($bytes < 1024);
		$size = sprintf("%.2f", ($bytes/1024)) . ' KB' if ($bytes >= 1024 && $bytes < 1048576);
		$size = sprintf("%.2f", ($bytes/1048576)) . ' MB' if ($bytes >= 1048576 && $bytes < 1073741824);
		$size = sprintf("%.2f", ($bytes/1073741824)) . ' GB' if ($bytes >= 1073741824 && $bytes < 1099511627776);
		$size = sprintf("%.2f", ($bytes/1099511627776)) . ' TB' if ($bytes >= 1099511627776);
	}
	elsif($type eq 'MHZ') {
		$size = sprintf("%.2f", ($bytes/1e-06)) . ' MHz' if ($bytes >= 1e-06 && $bytes < 0.001);
		$size = sprintf("%.2f", ($bytes*0.001)) . ' GHz' if ($bytes >= 0.001);
	}

	return $size;
}

sub getColor {
	my ($val) = @_;
	my $color_string = "";
	if($val < $RED_WARN) { $color_string = "<td bgcolor=\"$red\">".$val." %</td>"; }
	elsif($val < $ORANGE_WARN) { $color_string = "<td bgcolor=\"$orange\">".$val." %</td>"; }
	elsif($val < $YELLOW_WARN) { $color_string = "<td bgcolor=\"$yellow\">".$val." %</td>"; }
	else { $color_string = "<td>".$val." %</td>"; }

	return $color_string;
}

# http://andrewcantino.com/class/l2.html
sub power {
     my ($i,$t);
     my ($n, $p) = @_;
     $t = $n;
     for(my $i = 1; $i < $p; $i++) {
	  $t = $t * $n;
     }
     return $t;
}

#http://www.perlmonks.org/?node_id=17057
sub days_between {
	my ($start, $end) = @_;
	my ($y1, $m1, $d1) = split ("-", $start);
	my ($y2, $m2, $d2) = split ("-", $end);
	my $diff = mktime(0,0,0, $d2-1, $m2-1, $y2 - 1900) -  mktime(0,0,0, $d1-1, $m1-1, $y1 - 1900);
	return $diff / (60*60*24);
}

sub getUptime {
	my ($uptime) = @_;

	my @parts = gmtime($uptime);

	return $parts[7] . " days " . $parts[2] . " hours " . $parts[1] . " mins " . $parts[0] . " secs ";
}

sub giveMeDate {
	my ($date_format) = @_;
	my %dttime = ();
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	### begin_: initialize DateTime number formats
	$dttime{year }  = sprintf "%04d",($year + 1900);  ## four digits to specify the year
	$dttime{mon  }  = sprintf "%02d",($mon + 1);      ## zeropad months
	$dttime{mday }  = sprintf "%02d",$mday;           ## zeropad day of the month
	$dttime{wday }  = sprintf "%02d",$wday + 1;       ## zeropad day of week; sunday = 1;
	$dttime{yday }  = sprintf "%02d",$yday;           ## zeropad nth day of the year
	$dttime{hour }  = sprintf "%02d",$hour;           ## zeropad hour
	$dttime{min  }  = sprintf "%02d",$min;            ## zeropad minutes
	$dttime{sec  }  = sprintf "%02d",$sec;            ## zeropad seconds
	$dttime{isdst}  = $isdst;

	if($date_format eq 'MDYHMS') {
		$my_time = "$dttime{mon}-$dttime{mday}-$dttime{year} $dttime{hour}:$dttime{min}:$dttime{sec}";
	}
	elsif ($date_format eq 'YMD') {
		$my_time = "$dttime{year}-$dttime{mon}-$dttime{mday}";
	}
	return $my_time;
}
