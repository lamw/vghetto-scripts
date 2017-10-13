#!/usr/bin/perl -w
#
# Copyright (c) 2007 VMware, Inc.  All rights reserved.
#
# Modified 'vmclone.pl' from VMware's VI Perl Toolkit Utilites by William Lam
# http://engineering.ucsb.edu/~duonglt/vmware/vGhettoLinkedClone.html
#
# Modified by Chip Schweiss, chip.schweiss@wustl.edu
# Merged changes from vmclone2.pl (https://communities.vmware.com/docs/DOC-12746) by Bill Call
#   Allows for customization of either Windows or Linux VMs using the same schema.
# Added support for cloning via linked clones or copying.
# Added the ability to move the clone to specified folder
# Added a switch to control power on after cloning
# Added configuration to resolv.conf on Linux cloning

# TODO: Add resource reservations, annotations, CPU cores

use strict;
use warnings;
use Switch;

use FindBin;
use lib "$FindBin::Bin/../";
use lib "/etc/puppetmaster/global/bin/autodeploy/tools/vghetto-scripts/perl";

use VMware::VIRuntime;
use XML::LibXML;
use AppUtil::VMUtil;
use AppUtil::HostUtil;
use AppUtil::XMLInputUtil;

$Util::script_version = "1.0";

sub check_missing_value;

my %opts = (
   vmhost => {
      type => "=s",
      help => "The name of the host",
      required => 1,
   },
   vmname => {
      type => "=s",
      help => "The name of the Virtual Machine",
      required => 1,
   },
   vmname_destination => {
      type => "=s",
      help => "The name of the target virtual machine",
      required => 1,
   },
   filename => {
      type => "=s",
      help => "The name of the configuration specification file",
      required => 0,
      default => "../sampledata/vmclone.xml",
   },
   datastore => {
      type => "=s",
      help => "Name of the Datastore",
      required => 0,
   },
   snapname => {
      type => "=s",
      help => "Name of Snapshot from pristine base image",
      required => 1,
   },
   folder => {
      type => "=s",
      help => "Folder to place the clone in",
      required => 0,
   },
   clone_type => {
      type => "=s",
      help => "Specify the clone type to perform [linked|copy]",
      required => 0,
      default => 'linked',
   },
   convert => {
      type => "=s",
      help => "Convert destination disk type [source|sesparse]",
      required => 0,
      default => 'source',
   },
   grainsize => {
      type => "=s",
      help => "Grainsize for SE Sparse disk [default 1024k]",
      required => 0,
      default => 1024,
   },
   power_vm => {
      type => "=s",
      help => "Flag to specify whether or not to power on virtual machine after cloning"
           . "yes,no",
      required => 0,
      default => 'no',
   },
   customize_guest => {
      type => "=s",
      help => "Flag to specify whether or not to customize guest: yes,no",
      required => 0,
      default => 'no',
   },
   customize_vm => {
      type => "=s",
      help => "Flag to specify whether or not to customize virtual machine: "
            . "yes,no",
      required => 0,
      default => 'no',
   },
   schema => {
      type => "=s",
      help => "The name of the schema file",
      required => 0,
      default => "../schema/vmclone.xsd",
   },
);

Opts::add_options(%opts);
Opts::parse();
Opts::validate(\&validate);

Util::connect();

clone_vm();

Util::disconnect();


# Clone vm operation
# Gets destination host, compute resource views, and
# datastore info for creating the configuration
# specification to help create a clone of an existing
# virtual machine.
# ====================================================
sub clone_vm {
   my $vm_name = Opts::get_option('vmname');
   my $clone_name = Opts::get_option('vmname_destination');
   my $clone_type = Opts::get_option('clone_type');
   my $vm_snapshot_name = Opts::get_option('snapname');
   my $convert = Opts::get_option('convert');
   my $grainsize = Opts::get_option('grainsize');
   my $vm_views = Vim::find_entity_views(view_type => 'VirtualMachine',
                                        filter => {'name' =>$vm_name});
   my $parser = XML::LibXML->new();
   my $tree = $parser->parse_file(Opts::get_option('filename'));
   my $root = $tree->getDocumentElement;
   my @cspec = $root->findnodes('Virtual-Machine-Spec');
   my $clone_view;
   my $config_spec_operation;
   my @NIC;
   my $nic_network;
   my $nic_adapter;
   
   if(@$vm_views) {
      foreach (@$vm_views) {
         my $host_name =  Opts::get_option('vmhost');
         my $host_view = Vim::find_entity_view(view_type => 'HostSystem',
                                         filter => {'name' => $host_name});
                                         
         if (!$host_view) {
            Util::trace(0, "Host '$host_name' not found\n");
            return;
         }

         if ($host_view) {
            my $comp_res_view = Vim::get_view(mo_ref => $host_view->parent);
            my $ds_name = Opts::get_option('datastore');
            my %ds_info = HostUtils::get_datastore(host_view => $host_view,
                                     datastore => $ds_name,
                                     disksize => get_disksize());

            if ($ds_info{mor} eq 0) {
               if ($ds_info{name} eq 'datastore_error') {
                  Util::trace(0, "\nDatastore $ds_name not available.\n");
                  return;
               }
               if ($ds_info{name} eq 'disksize_error') {
                  Util::trace(0, "\nThe free space available is less than the"
                               . " specified disksize or the host"
                               . " is not accessible.\n");
                  return;
               }
            }


	    my ($vm_snapshot,$ref,$nRefs);
	    if(defined $_->snapshot) {
            	($ref, $nRefs) = find_snapshot_name ($_->snapshot->rootSnapshotList,
                                              $vm_snapshot_name);
      	    }
      	    if (defined $ref && $nRefs == 1) {
            	$vm_snapshot = Vim::get_view (mo_ref =>$ref->snapshot);
	    }
            else {
                Util::trace(0, "\nSnapshot $vm_snapshot_name not found. \n");
                return;
            }

	    my ($diskLocator,$relocate_spec,$diskType,$diskId);
	
	    my $vm_device = $_->config->hardware->device;
	    foreach my $vdevice (@$vm_device) {
	    	if($vdevice->isa('VirtualDisk')) {
			$diskId = $vdevice->key;
			last;
		}
  	    }
            
            
            if ($clone_type eq "copy") {
               $convert = "source";
               $relocate_spec = VirtualMachineRelocateSpec->new(datastore => $ds_info{mor},
                        host => $host_view,
                        pool => $comp_res_view->resourcePool);
            }
            elsif ($convert eq "sesparse" && Vim::get_service_content()->about->version eq "5.1.0") {
		my $newdiskName = "[" . $ds_name . "] " . $clone_name . "/" . $clone_name . ".vmdk";

	    	$diskLocator = VirtualMachineRelocateSpecDiskLocator->new(datastore => $ds_info{mor},
			diskBackingInfo => VirtualDiskFlatVer2BackingInfo->new(fileName => $newdiskName,
                                                                               diskMode => 'persistent',
                                                                               deltaDiskFormat => 'seSparseFormat',
                                                                               deltaGrainSize => $grainsize),
			diskId => $diskId);

		$relocate_spec = VirtualMachineRelocateSpec->new(datastore => $ds_info{mor},
                        host => $host_view,
                        diskMoveType => "createNewChildDiskBacking",
                        pool => $comp_res_view->resourcePool,
			disk => [$diskLocator]);
	    } else {
                $relocate_spec = VirtualMachineRelocateSpec->new(datastore => $ds_info{mor},
                        host => $host_view,
                        diskMoveType => "createNewChildDiskBacking",
                        pool => $comp_res_view->resourcePool);
	    }

            my $clone_spec ;
            my $config_spec;
            my $customization_spec;
            my $poweron;
            
            # We will trigger the power on after cloning if spceified
            $poweron = 0;
            
            
            
            if ((Opts::get_option('customize_vm') eq "yes")
                && (Opts::get_option('customize_guest') ne "yes")) {
               $config_spec = get_config_spec();
               $clone_spec = VirtualMachineCloneSpec->new(powerOn => 0,
                                                          template => 0,
						          snapshot => $vm_snapshot,
                                                          location => $relocate_spec,
                                                          config => $config_spec,
                                                          );
            }
            elsif ((Opts::get_option('customize_guest') eq "yes")
                && (Opts::get_option('customize_vm') ne "yes")) {
               $customization_spec = VMUtils::get_customization_spec
                                              (Opts::get_option('filename'));
               $clone_spec = VirtualMachineCloneSpec->new(powerOn => $poweron,
                                                          template => 0,
						          snapshot => $vm_snapshot,
                                                          location => $relocate_spec,
                                                          customization => $customization_spec,
                                                          );
            }
            elsif ((Opts::get_option('customize_guest') eq "yes")
                && (Opts::get_option('customize_vm') eq "yes")) {
               $customization_spec = VMUtils::get_customization_spec
                                              (Opts::get_option('filename'));
               $config_spec = get_config_spec();
               $clone_spec = VirtualMachineCloneSpec->new(
                                                   powerOn => $poweron,
                                                   template => 0,
						   snapshot => $vm_snapshot,
                                                   location => $relocate_spec,
                                                   customization => $customization_spec,
                                                   config => $config_spec,
                                                   );
            }
            else {
               $clone_spec = VirtualMachineCloneSpec->new(
                                                   powerOn => $poweron,
                                                   template => 0,
						   snapshot => $vm_snapshot,
                                                   location => $relocate_spec,
                                                   );
            }
            
            $Data::Dumper::Sortkeys = 1; #Sort the keys in the output
            $Data::Dumper::Deepcopy = 1; #Enable deep copies of structures
            $Data::Dumper::Indent = 1;   #Enable enough indentation to read the output
            print Dumper ($customization_spec) . "\n";
            
            ##
            # Do the actual clone
            ##
            
            Util::trace (0, "\nLink Cloning virtual machine '" . $clone_name . "' from '" . $vm_name . "' ...\n");

            eval {
               $_->CloneVM(folder => $_->parent,
                              name => Opts::get_option('vmname_destination'),
                              spec => $clone_spec);
               Util::trace (0, "\nClone '$clone_name' of virtual machine"
                             . " '$vm_name' successfully created.\n");
            };

            if ($@) {
               if (ref($@) eq 'SoapFault') {
                  if (ref($@->detail) eq 'FileFault') {
                     Util::trace(0, "\nFailed to access the virtual "
                                    ." machine files\n");
                  }
                  elsif (ref($@->detail) eq 'InvalidState') {
                     Util::trace(0,"The operation is not allowed "
                                   ."in the current state.\n");
                  }
                  elsif (ref($@->detail) eq 'NotSupported') {
                     Util::trace(0," Operation is not supported by the "
                                   ."current agent \n");
                  }
                  elsif (ref($@->detail) eq 'VmConfigFault') {
                     Util::trace(0,
                     "Virtual machine is not compatible with the destination host.\n");
                  }
                  elsif (ref($@->detail) eq 'InvalidPowerState') {
                     Util::trace(0,
                     "The attempted operation cannot be performed "
                     ."in the current state.\n");
                  }
                  elsif (ref($@->detail) eq 'DuplicateName') {
                     Util::trace(0,
                     "The name '$vm_name' already exists\n");
                  }
                  elsif (ref($@->detail) eq 'NoDisksToCustomize') {
                     Util::trace(0, "\nThe virtual machine has no virtual disks that"
                                  . " are suitable for customization or no guest"
                                  . " is present on given virtual machine" . "\n");
                  }
                  elsif (ref($@->detail) eq 'HostNotConnected') {
                     Util::trace(0, "\nUnable to communicate with the remote host, "
                                    ."since it is disconnected" . "\n");
                  }
                  elsif (ref($@->detail) eq 'UncustomizableGuest') {
                     Util::trace(0, "\nCustomization is not supported "
                                    ."for the guest operating system" . "\n");
                  }
                  else {
                     Util::trace (0, "Fault" . $@ . ""   );
                  }
               }
               else {
                  Util::trace (0, "Fault" . $@ . ""   );
               }
            }
            else {
               # Clone was sucessful.  Perform post clone tasks.
               
               # Move to a folder if specified
               my $vm_folder = Opts::get_option('folder');
               if ($vm_folder ne "") {
                  move_vm_to_folder($clone_name, $vm_folder);
               }
               
               # Setup NICs and thier backing
               foreach (@cspec) {
                  if ($_->findvalue('NIC')) {
                     # Network adapters are being defined.   Destroy existing ones first.
                     $clone_view = Vim::find_entity_view(view_type => 'VirtualMachine',
                                                         filter =>{ 'name' => $clone_name});
                     if ($clone_view) {
                        my $devices = $clone_view->config->hardware->device;
                        foreach my $vnic_device (@$devices){
                           if (index($vnic_device->deviceInfo->label, "Network adapter " ) != -1 ) {
                              #remove the old vNIC
                              Util::trace(0, "\nRemoving NIC " . ref($vnic_device) );
                              $config_spec_operation = VirtualDeviceConfigSpecOperation->new('remove');
                              my $vm_dev_spec = VirtualDeviceConfigSpec->new(device => $vnic_device,
                                                                             operation => $config_spec_operation);
                              my $vmChangespec = VirtualMachineConfigSpec->new(deviceChange => [ $vm_dev_spec ] );
                              eval{
                                 $clone_view->ReconfigVM_Task(spec => $vmChangespec);  
                              };
                              if ($@) {
                                 Util::trace(0, "\nFailed to remove NIC.");
                              } else {
                                 Util::trace(0, "\nSuccess.");
                              }
                           }
                           
                        }
                     } else {
                        Util::trace(0, "\nCould not find newly created clone");
                        exit 1
                     }
                     
                     
                     @NIC = $_->findnodes('NIC');
                     # Add back network adapters as defined.
                     $config_spec_operation = VirtualDeviceConfigSpecOperation->new('add');
                     foreach (@NIC) {
                        $nic_network = $_->findvalue('Network');
                        if ( $_->findvalue('Adapter')) {
                           $nic_adapter = $_->findvalue('Adapter');
                        } else {
                           $nic_adapter = "vmxnet3";
                        }
                        
                        my $backing_info = VirtualEthernetCardNetworkBackingInfo->new(deviceName => $nic_network);
                        my $newNetworkDevice;
                        
                        switch($nic_adapter) {
                           case 'e1000' {
                              $newNetworkDevice = VirtualE1000->new(key => -1,
                                                                    backing => $backing_info,
                                                                    addressType => 'Assigned');
                           }
                           case 'pcnet' {
                              $newNetworkDevice = VirtualPCNet32->new(key => -1,
                                                                      backing => $backing_info,
                                                                      addressType => 'Assigned');
                           }
                           case 'vmxnet2' {
                              $newNetworkDevice = VirtualVmxnet2->new(key => -1,
                                                                      backing => $backing_info,
                                                                      addressType => 'Assigned');
                           }
                           case 'vmxnet3' {
                              $newNetworkDevice = VirtualVmxnet3->new(key => -1,
                                                                      backing => $backing_info,
                                                                      addressType => 'Assigned');
                           }
                           else {
                              Util::trace(0, "\nInvalid adapter path $nic_adapter.");
                           }
                        }
                        my $vm_dev_spec = VirtualDeviceConfigSpec->new(device => $newNetworkDevice,
                                                                       operation => $config_spec_operation);
                        my $vmChangespec = VirtualMachineConfigSpec->new(deviceChange => [ $vm_dev_spec ] );
                        
                        eval {
                           $clone_view->ReconfigVM_Task(spec => $vmChangespec);
                        };
                        if ($@) {
                           Util::trace(0, "\nFailed to add $nic_adapter on $nic_network to $clone_name.");
                        } else {
                           Util::trace(0, "\nSuccessfully added $nic_adapter on $nic_network to $clone_name.");
                        }
                        
                        
                     }
                  }
                  
               }
               
               # Power on the VM if specified.
               if (Opts::get_option('power_vm') eq "yes") {
                  $clone_view = Vim::find_entity_view(
                     view_type => "VirtualMachine",
                     filter => { 'name' => $clone_name },
                     );
                  eval {
                     $clone_view->PowerOnVM_Task();
                  };
                  if ($@) {
                     Util::trace(0, "\nFailed to power on $clone_name" );
                  } else {
                     Util::trace(0, "\nSuccessfully powered on $clone_name" );
                  }    
               }
               
            }
         }
      }
   }
   else {
      Util::trace (0, "\nNo virtual machine found with name '$vm_name'\n");
   }
}

sub move_vm_to_folder {
   my ($vmname, $folder) = @_;
   my @subdirs;
   
   #Get the VM object
   my $current_views = Vim::find_entity_views((view_type => 'VirtualMachine'), filter => { name => $vmname } );
   my $vm_moref = shift @$current_views;
   
   # Separate the folder into its parts
   @subdirs = split(/\//,$folder);
   
   # Grab the root folder 'vm'
   my $folder_views = Vim::find_entity_views(view_type => 'Folder', filter => { name => 'vm' });
   my $vm_folder_ref = shift (@$folder_views);
   
   my $current_ref = $vm_folder_ref;
   
   foreach my $dir(@subdirs) {
      #Find the child with the name of $dir and change the current_ref to it
      my $children = $current_ref->{childEntity};
      foreach my $child(@$children) {
         my $child_ref = Vim::get_view(mo_ref => $child);
         if ($child_ref->{mo_ref}->{type} eq "Folder") {
            if ($child_ref->{name} eq $dir) {
               $current_ref = $child_ref;
               last;
            }
         }
      }
   }
   
   $current_ref->MoveIntoFolder_Task(list => $vm_moref);  
}

sub find_snapshot_name {
   my ($tree, $name) = @_;
   my $ref = undef;
   my $count = 0;
   foreach my $node (@$tree) {
      if ($node->name eq $name) {
         $ref = $node;
         $count++;
      }
      my ($subRef, $subCount) = find_snapshot_name($node->childSnapshotList, $name);
      $count = $count + $subCount;
      $ref = $subRef if ($subCount);
   }
   return ($ref, $count);
}

#Gets the config_spec for customizing the memory, number of cpu's
# and returns the spec
sub get_config_spec() {

   my $parser = XML::LibXML->new();
   my $tree = $parser->parse_file(Opts::get_option('filename'));
   my $root = $tree->getDocumentElement;
   my @cspec = $root->findnodes('Virtual-Machine-Spec');
   my $vmname ;
   my $vmhost  ;
   my $guestid;
   my $datastore;
   my $disksize = 4096;  # in KB;
   my $memory = 256;  # in MB;
   my $num_cpus = 1;
   my $nic_network;
   my $nic_poweron = 1;

   foreach (@cspec) {
   
      if ($_->findvalue('Guest-Id')) {
         $guestid = $_->findvalue('Guest-Id');
      }
      if ($_->findvalue('Memory')) {
         $memory = $_->findvalue('Memory');
      }
      if ($_->findvalue('Number-of-CPUS')) {
         $num_cpus = $_->findvalue('Number-of-CPUS');
      }
      $vmname = Opts::get_option('vmname_destination');
   }

   my $vm_config_spec = VirtualMachineConfigSpec->new(
                                                  name => $vmname,
                                                  memoryMB => $memory,
                                                  numCPUs => $num_cpus,
                                                  guestId => $guestid );
   return $vm_config_spec;
}

sub get_disksize {
   my $disksize = -1;
   my $parser = XML::LibXML->new();
   
   eval {
      my $tree = $parser->parse_file(Opts::get_option('filename'));
      my $root = $tree->getDocumentElement;
      my @cspec = $root->findnodes('Virtual-Machine-Spec');

      foreach (@cspec) {
         $disksize = $_->findvalue('Disksize');
      }
   };
   
   return $disksize;
}

sub find_disk {
	my %args = @_;
	my $vm = $args{vm};
	my $name = $args{fileName};

	my $devices = $vm->config->hardware->device;
	foreach my $device(@$devices) {
		if($device->isa('VirtualDisk')) {
			return $device;
		}
	} 
}

# check missing values of mandatory fields
sub check_missing_value {
   my $valid= 1;
   my $filename = Opts::get_option('filename');
   my $parser = XML::LibXML->new();
   my $tree = $parser->parse_file($filename);
   my $root = $tree->getDocumentElement;
   my @cust_spec = $root->findnodes('Customization-Spec');
   my $total = @cust_spec;
   if (!$cust_spec[0]->findvalue('Auto-Logon')) {
      Util::trace(0,"\nERROR in '$filename':\n autologon value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Virtual-Machine-Name')) {
      Util::trace(0,"\nERROR in '$filename':\n computername value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Timezone')) {
      Util::trace(0,"\nERROR in '$filename':\n timezone value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Domain')) {
      Util::trace(0,"\nERROR in '$filename':\n domain value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Domain-User-Name')) {
      Util::trace(0,"\nERROR in '$filename':\n domain_user_name value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Domain-User-Password')) {
      Util::trace(0,"\nERROR in '$filename':\n domain_user_password value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Full-Name')) {
      Util::trace(0,"\nERROR in '$filename':\n fullname value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Orgnization-Name')) {
      Util::trace(0,"\nERROR in '$filename':\n Orgnization name value missing ");
      $valid = 0;
   }
   return $valid;
}

sub validate {
   my $valid= 1;
   if ((Opts::get_option('customize_vm') eq "yes")
                || (Opts::get_option('customize_guest') eq "yes")) {

      $valid = XMLValidation::validate_format(Opts::get_option('filename'));
      if ($valid == 1) {
         $valid = XMLValidation::validate_schema(Opts::get_option('filename'),
	                                         Opts::get_option('schema'));
         if ($valid == 1) {
            $valid = check_missing_value();
         }
      }
   }

    if (Opts::option_is_set('customize_vm')) {
       if ((Opts::get_option('customize_vm') ne "yes")
             && (Opts::get_option('customize_vm') ne "no")) {
          Util::trace(0,"\nMust specify 'yes' or 'no' for customize_vm option");
          $valid = 0;
       }
       
    }
    if (Opts::option_is_set('customize_guest')) {
       if ((Opts::get_option('customize_guest') ne "yes")
             && (Opts::get_option('customize_guest') ne "no")) {
          Util::trace(0,"\nMust specify 'yes' or 'no' for customize_guest option");
          $valid = 0;
       }
    }
    if (Opts::option_is_set('clone_type')) {
       if ((Opts::get_option('clone_type') ne "linked")
             && (Opts::get_option('clone_type') ne "copy")) {
          Util::trace(0,"\nMust specify 'linked' or 'copy' for clone_type option");
          $valid = 0;
       }
    }
    if (Opts::option_is_set('convert')) {
       if ((Opts::get_option('convert') ne "source")
             && (Opts::get_option('convert') ne "sesparse")) {
          Util::trace(0,"\nMust specify 'source' or 'sesparse' for convert option");
          $valid = 0;
       }
    }
    if (Opts::option_is_set('power_vm')) {
       if ((Opts::get_option('power_vm') ne "yes")
             && (Opts::get_option('power_vm') ne "no")) {
          Util::trace(0,"\nMust specify 'yes' or 'no' for power_vm option");
          $valid = 0;
       }
    }
    
    
   return $valid;
}



__END__

=head1 NAME

vmclone.pl - Perform clone operation on virtual machine and
             customize operation on both virtual machine and the guest.

=head1 SYNOPSIS

 vmclone.pl [options]

=head1 DESCRIPTION

VI Perl command-line utility allows you to clone a virtual machine. You 
can customize the virtual machine or the guest operating system as part 
of the clone operation.

=head1 OPTIONS

=head2 GENERAL OPTIONS

=over

=item B<vmhost>

Required. Name of the host containing the virtual machine.

=item B<vmname>

Required. Name of the virtual machine whose clone is to be created.

=item B<vmname_destination>

Required. Name of the clone virtual machine which will be created.

=item B<datastore>

Optional. Name of a data center. If none is given, the script uses the default data center.

=back

=head2 CUSTOMIZE GUEST OPTIONS

=over

=item B<customize_guest>

Required. Customize guest is used to customize the network settings of the guest
operating system. Options are Yes/No.

=item B<filename>

Required. It is the name of the file in which values of parameters to be
customized is written e.g. --filename  clone_vm.xml.

=item B<schema>

Required. It is the name of the schema which validates the filename.

=back

=head2 CUSTOMIZE VM OPTIONS

=over

=item B<customize_vm>

Required. customize_vm is used to customize the virtual machine settings
like disksize, memory. If yes is written it will be customized.

=item B<filename>

Required. It is the name of the file in which values of parameters to be
customized is written e.g. --filename  clone_vm.xml.

=item B<schema>

Required. It is the name of the schema which validates the filename.

=back

=head2 INPUT PARAMETERS

=head3 GUEST CUSTOMIZATION

The parameters for customizing the guest os are specified in an XML
file. The structure of the input XML file is:

 <Specification>
  <Customization-Spec>
  </Customization-Spec>
 </Specification>

Following are the input parameters:

=over

=item B<Auto-Logon>

Required. Flag to specify whether auto logon should be enabled or disabled.

=item B<Virtual-Machine-Name>

Required. Name of the virtual machine to be created.

=item B<Timezone>

Required. Time zone property of guest OS.

=item B<Domain>

Required. The domain that the virtual machine should join.

=item B<Domain-User-Name>

Required. The domain user account used for authentication.

=item B<Domain-User-Password>

Required. The password for the domain user account used for authentication.

=item B<Full-Name>

Required. User's full name.

=item B<Orgnization-Name>

Required. User's organization.

=back

=head3 VIRTUAL MACHINE CUSTOMIZATION

The parameters for customizing the virtual machine are specified in an XML
file. The structure of the input XML file is:

   <Specification>
    <Config-Spec-Spec>
       <!--Several parameters like Guest-Id, Memory, Disksize, Number-of-CPUS etc-->
    </Config-Spec>
   </Specification>

Following are the input parameters:

=over

=item B<Guest-Id>

Required. Short guest operating system identifier.

=item B<Memory>

Required. Size of a virtual machine's memory, in MB.

=item B<Number-of-CPUS>

Required. Number of virtual processors in a virtual machine.

=back

See the B<vmcreate.pl> page for an example of a virtual machine XML file.

=head1 EXAMPLES

Making a clone without any customization:

 perl vmclone.pl --username username --password mypassword
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination DVM99
                 --url https://<ipaddress>:<port>/sdk/webService

If datastore is given:

 perl vmclone.pl --username username --password mypassword
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination DVM99
                 --url https://<ipaddress>:<port>/sdk/webService --datastore storage1

Making a clone and customizing the VM:

 perl vmclone.pl --username myusername --password mypassword
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination Clone_VM
                 --url https://<ipaddress>:<port>/sdk/webService --customize_vm yes
                 --filename clone_vm.xml --schema clone_schema.xsd

Making a clone and customizing the guestOS:

 perl vmclone.pl --username myuser --password mypassword --operation clone
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination DVM99
                 --url https://<ipaddress>:<port>/sdk/webService --customize_guest yes
                 --filename clone_vm.xml --schema clone_schema.xsd

Making a clone and customizing both guestos and VM:

 perl vmclone.pl --username myuser --password mypassword
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination DVM99
                 --url https://<ipaddress>:<port>/sdk/webService --customize_guest yes
                 --customize_vm yes --filename clone_vm.xml --schema clone_schema.xsd

All the parameters which are to be customized are written in the vmclone.xml file.

=head1 SUPPORTED PLATFORMS

All operations supported on VirtualCenter 2.0.1 or later.

To perform the clone operation, you must connect to a VirtualCenter server.

