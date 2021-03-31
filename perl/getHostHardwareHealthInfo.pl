#!/usr/bin/perl -w
# Author: William Lam
# Website: www.virtuallyghetto.com
# Reference: http://communities.vmware.com/docs/DOC-11641

use strict;
use warnings;
use VMware::VIRuntime;
use VMware::VILib;
use Net::SMTP;

#################
# EMAIL CONF
#################

my $SEND_MAIL = "no";
my $EMAIL_HOST = "emailserver";
my $EMAIL_DOMAIN = "localhost.localdomain";
my $EMAIL_TO = 'William Lam <william@primp-industries.com>';
my $EMAIL_FROM = 'vMA <vMA@primp-industries.com>';

# define custom options for vm and target host
my %opts = (
   'hostfile' => {
      type => "=s",
      help => "List of hosts to perform operation on",
      required => 0,
   },
   'reportname' => {
      type => "=s",
      help => "Name of the report to email out",
      required => 0,
      default => 'vmwareHostHardwareHealthReport.html',
   },
   'monitortype' => {
      type => "=s",
      help => "Monitor some or all hosts within vCenter [some|all]",
      required => 0,
   },
);

# read and validate command-line parameters 
Opts::add_options(%opts);
Opts::parse();
Opts::validate();
Util::connect();
my $hosttype = &validateConnection('3.5.0','undef','both');

my ($host_view,$task_ref,$hostfile,$reportname,$monitortype);
my @host_list = ();
my $debug = 0;
my $report_name = "VMware Host Hardware Health Report";

$hostfile = Opts::get_option("hostfile");
$reportname = Opts::get_option("reportname");
$monitortype = Opts::get_option("monitortype");

&checkHosts();
&endReportCreation();

Util::disconnect();

sub checkHosts {
	if($hosttype eq 'VirtualCenter') {
		unless($monitortype) {
			Util::disconnect();
                        print "Error: When connecting to vCenter, you must specify --monitortype and specify if you want to monitor \"some\" or \"all\" hosts!\n\n";
			exit 1;
		}
		if($monitortype eq 'some') {
			unless($hostfile) {
				Util::disconnect();
				print "Error: When connecting to vCenter, you must specify --hostfile and provide input file of the ESX(i) hosts you would like to check!\n\n";
				exit 1;
			}
			&startReportCreation();
			&processFile($hostfile);
			foreach my $host_name( @host_list ) {
                		chomp($host_name);

                		$host_view = Vim::find_entity_view(view_type => 'HostSystem', filter => { 'name' => $host_name});
				&getHardwareHealthInfo($host_view);
			}	
		} else {
			&startReportCreation();
			my $host_views = Vim::find_entity_views(view_type => 'HostSystem');
			foreach(@$host_views) {
				&getHardwareHealthInfo($_);
			}
		}
	} else {
		&startReportCreation();
		$host_view = Vim::find_entity_view(view_type => 'HostSystem');
		&getHardwareHealthInfo($host_view);
	}
}

sub getHardwareHealthInfo {
	my ($host_view) = @_;

	if($host_view) {
		my $host_name = $host_view->name;
		print REPORT_OUTPUT "<div id=\"wrapper\">\n";

		my $hardwareSystem = Vim::get_view(mo_ref => $host_view->configManager->healthStatusSystem);
		my ($cpu,$mem,$storage,@sensors);
		if($hardwareSystem->runtime->hardwareStatusInfo) {	
			###########
			# CPU
			###########
			my $cpuStatus = $hardwareSystem->runtime->hardwareStatusInfo->cpuStatusInfo;
			foreach(@$cpuStatus) {
				if($_->status->key ne 'Green' || $debug eq 1) {
					$cpu .= "\t\t<div id=\"content-main\" style=\"color:" . $_->status->key ."\"><p>". $_->name ."</p></div>\n";
				}
			}

			###########
			# MEMORY
			###########
			my $memStatus = $hardwareSystem->runtime->hardwareStatusInfo->memoryStatusInfo;
			foreach(@$memStatus) {
				if($_->status->key ne 'Green' || $debug eq 1) {
					$mem .= "\t\t<div id=\"content-main\" style=\"color:" . $_->status->key ."\"><p>". $_->name ."</p></div>\n";
       	   	             }
			}

			###########
			# STORAGE 
			###########
			my $stoStatus = $hardwareSystem->runtime->hardwareStatusInfo->storageStatusInfo;
			foreach(@$stoStatus) {
				if($_->status->key ne 'Green' || $debug eq 1) {
					$storage .= "\t\t<div id=\"content-main\" style=\"color:" . $_->status->key ."\"><p>". $_->name ."</p></div>\n";
                       		}
               		}
		}
			
		if($hardwareSystem->runtime->systemHealthInfo) {
			##########################
			# OTHER SYSTEM COMPONENTS
			##########################
			my $sensorInfo = $hardwareSystem->runtime->systemHealthInfo->numericSensorInfo;
			foreach(@$sensorInfo) {
				if($_->healthState && $_->healthState->label ne 'Green' || $debug eq 1) {
					my $reading = $_->currentReading * $_->unitModifier; 
					my $units;
					if($_->rateUnits) {
						$units = $_->baseUnits . "/" . $_->rateUnits;
					} else { $units = $_->baseUnits; }
					my $sensor_string = $_->sensorType . "==" . "\t\t<div id=\"content-main\" style=\"color:" . $_->healthState->key ."\"><p>". $_->name ." --- ". $reading ." ". $units ."</p></div>\n";
					push @sensors,$sensor_string;
				}
			}
		}

	
		##################
		# PRINT SUMMARY
		##################

		#everything A okay
		my $build = $host_view->summary->config->product->fullName if($host_view->summary->config->product->fullName);
		if(!$cpu && !$mem && !$storage && !@sensors) {
			print REPORT_OUTPUT "\t<table><tr><td><div id=\"header\" style=\"color:blue\">$host_name ($build)</div></td><td><div id=\"content-good\" style=\"color:green\">[ ALL GOOD ]</div></td></tr></table>\n";
             	} else {
			print REPORT_OUTPUT "\t<div id=\"header\" style=\"color:blue\">$host_name ($build)</div>\n";
		}

		#something was bad
		if($cpu) { 
			print REPORT_OUTPUT "\t<div id=\"content\"><p>CPU COMPONENTS</p></div>\n";
			print REPORT_OUTPUT $cpu;
		}
		if($mem) { 
			print REPORT_OUTPUT "\t<div id=\"content\"><p>MEMORY COMPONENTS</p></div>\n";
			print REPORT_OUTPUT $mem; 
		}
		if($storage) { 
			print REPORT_OUTPUT "\t<div id=\"content\"><p>STORAGE COMPONENTS</p></div>\n";
			print REPORT_OUTPUT $storage; 
		}
		if(@sensors) {
			my %seen;
			foreach(@sensors) {
				my ($component,$sensor) = split('==',$_);
				if(!$seen{$component}) {
					$seen{$component} = "yes";
					my $type = uc $component;
					print REPORT_OUTPUT "\t<div id=\"content\"><p>$type COMPONENTS</p></div>\n";
				}
				if($seen{$component}) { 
					print REPORT_OUTPUT $sensor;
				}
			}
		}
		print REPORT_OUTPUT "</div>\n"	
	}
}

if($SEND_MAIL eq "yes") {
        &sendMail();
}

########################
# HELPER FUNCTIONS
########################

sub sendMail {
        my $smtp = Net::SMTP->new($EMAIL_HOST ,Hello => $EMAIL_DOMAIN,Timeout => 30,);

        unless($smtp) {
                die "Error: Unable to setup connection with email server: \"" . $EMAIL_HOST . "\"!\n";
        }

        open(DATA, $reportname) || die("Could not open the file");
        my @report = <DATA>;
        close(DATA);

        my $boundary = 'frontier';

        $smtp->mail($EMAIL_FROM);
        $smtp->to($EMAIL_TO);
        $smtp->data();
        $smtp->datasend('From: '.$EMAIL_FROM."\n");
        $smtp->datasend('To: '.$EMAIL_TO."\n");
        $smtp->datasend('Subject: $reportname'.giveMeDate('MDYHMS')."\n");
        $smtp->datasend("MIME-Version: 1.0\n");
        $smtp->datasend("Content-type: multipart/mixed;\n\tboundary=\"$boundary\"\n");
        $smtp->datasend("\n");
        $smtp->datasend("--$boundary\n");
        $smtp->datasend("Content-type: text/plain\n");
        $smtp->datasend("Content-Disposition: quoted-printable\n");
        $smtp->datasend("\nReport $reportname is attached!\n");
        $smtp->datasend("--$boundary\n");
        $smtp->datasend("Content-Type: application/text; name=\"$reportname\"\n");
        $smtp->datasend("Content-Disposition: attachment; filename=\"$reportname\"\n");
        $smtp->datasend("\n");
        $smtp->datasend("@report\n");
        $smtp->datasend("--$boundary--\n");
        $smtp->dataend();
        $smtp->quit;
}

# Subroutine to process the input file
sub processFile {
        my ($vmlist) =  @_;
        my $HANDLE;
        open (HANDLE, $vmlist) or die("ERROR: Can not locate \"$vmlist\" input file!\n");
        my @lines = <HANDLE>;
        my @errorArray;
        my $line_no = 0;

        close(HANDLE);
        foreach my $line (@lines) {
                $line_no++;
                &TrimSpaces($line);

                if($line) {
                        if($line =~ /^\s*:|:\s*$/){
                                print "Error in Parsing File at line: $line_no\n";
                                print "Continuing to the next line\n";
                                next;
                        }
                        my $host = $line;
                        &TrimSpaces($host);
                        push @host_list,$host;
                }
        }
}

sub TrimSpaces {
        foreach (@_) {
                s/^\s+|\s*$//g
        }
}

sub startReportCreation {
	print "Generating $report_name \"$reportname\" ...\n\n";
	open(REPORT_OUTPUT, ">$reportname");
	
	my $date = " --- Date: ".giveMeDate('MDYHMS');
	my $html_start = <<HTML_START;
<html>
<title>$report_name</title>
<META NAME="AUTHOR" CONTENT="William Lam">

<style type="text/css">
	body {
		font-family:arial,helvetica,sans-serif;
		font-size:12px;
		background-color:#E0D8E0;
	}
	#title {
		margin:0px auto;
		padding:10px;
		font-size:16px;
		font-weight: bold;
		font-color: black;
		text-align: center;
	}
	#wrapper {
		margin:0px auto;
		border:1px solid #bbb;
		padding:10px;
		width: 80%;
	}
	#header {
		font-size:14px;
		font-weight: bold;
		border:1px solid #bbb;
		height:10px;
		padding:10px;
	}
	#content-good {
		font-size:13px;
		font-weight: bold;
		border:1px solid #bbb;
		height:10px;
		padding:10px;
	}
	#content {
		font-weight: bold;
		margin-top:1px;
	}
	#content-main {
		margin-left:10px;
		width:666px;
		height:10px;
	}
</style>

<div id="title">$report_name $date</div>

HTML_START

	print REPORT_OUTPUT $html_start;
}

sub endReportCreation {
	my $html_end = <<HTML_END;
</html>
HTML_END
	print REPORT_OUTPUT $html_end;
	close(REPORT_OUTPUT);
}

sub giveMeDate {
        my ($date_format) = @_;
        my %dttime = ();
	my $my_time;
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

sub validateConnection {
        my ($host_version,$host_license,$host_type) = @_;
        my $service_content = Vim::get_service_content();
        my $licMgr = Vim::get_view(mo_ref => $service_content->licenseManager);

        ########################
        # CHECK HOST VERSION
        ########################
        if(!$service_content->about->version ge $host_version) {
                Util::disconnect();
                print "This script requires your ESX(i) host to be greater than $host_version\n\n";
                exit 1;
        }

        ########################
        # CHECK HOST LICENSE
        ########################
        my $licenses = $licMgr->licenses;
        foreach(@$licenses) {
                if($_->editionKey eq 'esxBasic' && $host_license eq 'licensed') {
                        Util::disconnect();
                        print "This script requires your ESX(i) be licensed, the free version will not allow you to perform any write operations!\n\n";
                        exit 1;
                }
        }

        ########################
        # CHECK HOST TYPE
        ########################
        if($service_content->about->apiType ne $host_type && $host_type ne 'both') {
                Util::disconnect();
                print "This script needs to be executed against $host_type\n\n";
                exit 1
        }

        return $service_content->about->apiType;
}
