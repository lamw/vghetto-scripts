#!/usr/bin/perl -w
# Author: William Lam
# Website: www.williamlam.com
# Reference: http://communities.vmware.com/docs/DOC-11213

use strict;
use warnings;
use VMware::VILib;
use VMware::VIRuntime;

my %opts = (
   vmname => {
      type => "=s",
      help => "Name of VM to add/update advanced paraemter",
      required => 1,
   },
   datastore => {
      type => "=s",
      help => "Name of the datastore where VMDK is located in",
      required => 0,
   },
   vmdkname => {
      type => "=s",
      help => "Name of the VMDK to add (e.g. myvmdk.vmdk)",
      required => 1,
   },
   operation  => {
      type => "=s",
      help => "Operation to perform [add|remove|destroy]",
      required => 1,
   },
);

Opts::add_options(%opts);
Opts::parse();
Opts::validate();
Util::connect();

my $vmdkname = Opts::get_option('vmdkname');
my $datastore = Opts::get_option('datastore');
my $vmname = Opts::get_option('vmname');
my $operation = Opts::get_option('operation');
my $fullpath = undef;

my $vm = Vim::find_entity_view(view_type => 'VirtualMachine',
			filter => {"config.name" => $vmname});

unless ($vm) {
	print "Unable to find VM: \"$vmname\"!\n";
        exit 1
}

if($operation eq 'add') {
	unless($datastore) {
		Util::disconnect();
                die "For \"add\" operation, you need the following parmas defined: datastore!\n";
	}
	&addExistingVMDK($vm,$datastore,$vmdkname);
} elsif($operation eq 'remove') {
	&removeVMDK($vm,$vmdkname,$datastore,0);
} elsif($operation eq 'destroy') {
	&removeVMDK($vm,$vmdkname,$datastore,1);
}

Util::disconnect();

sub removeVMDK {
	my ($vm,$file,$dsname,$des) = @_;

	my ($disk,$config_spec_operation, $config_file_operation);
        $config_spec_operation = VirtualDeviceConfigSpecOperation->new('remove');
        $config_file_operation = VirtualDeviceConfigSpecFileOperation->new('destroy');

        $disk = &find_disk(vm => $vm,
                fileName => $file,
                datastore => $dsname
        );

        if($disk) {
		my ($devspec,$op_string1,$op_string2);
		if($des eq 1) {
                	$devspec = VirtualDeviceConfigSpec->new(operation => $config_spec_operation,
                        	device => $disk,
                        	fileOperation => $config_file_operation
                	);
			$op_string1 = "destroy";
			$op_string2 = "destroyed";
		} else {
			$devspec = VirtualDeviceConfigSpec->new(operation => $config_spec_operation,
                                device => $disk
			);
			$op_string1 = "remove";
                        $op_string2 = "removed";
		}

                my $vmspec = VirtualMachineConfigSpec->new(deviceChange => [$devspec] );
                eval {
			print "Reconfiguring \"" . $vm->name . "\" to " . $op_string1 . " VMDK: \"$file\" ...\n";
                        my $task = $vm->ReconfigVM_Task( spec => $vmspec );
			my $msg = "Sucessfully " . $op_string2 . " VMDK to \"$vmname\"!\n";
                        &getStatus($task,$msg);
                };
                if($@) {
                        print "Error: " . $@ . "\n";
                }
        } else {
                print "Error: Unable to remove VMDK from VM: \"" . $vm->name . "\"\n";
        }
}

sub addExistingVMDK {
	my ($vm,$dsname,$file) = @_;

        my $ds = &find_datastore(vm => $vm, datastore => $dsname);

	unless($ds) {
		Util::disconnect();
		die "Error: Unable to locate datastore: \"" . $dsname . "\"\n";
	}

	my $size = &find_vmdk(datastore => $ds, file => $file);

	unless($size) {
		Util::disconnect();
                die "Error: Unable to locate VMDK: \"$file\"\n";
	}

	my $controller = &find_device(vm => $vm,
                                   controller => "SCSI controller 0"
        );

	my $controllerKey = $controller->key;
        my $unitNumber = $#{$controller->device} + 1;

        my $disk_backing_info = VirtualDiskFlatVer2BackingInfo->new(datastore => $ds,
                fileName => $fullpath,
                diskMode => "persistent"
        );

        my $disk = VirtualDisk->new(controllerKey => $controllerKey,
        	unitNumber => $unitNumber,
                key => -1,
                backing => $disk_backing_info,
                capacityInKB => $size
        );

        my $devspec = VirtualDeviceConfigSpec->new(operation => VirtualDeviceConfigSpecOperation->new('add'),
        	device => $disk,
        );

        my $vmspec = VirtualMachineConfigSpec->new(deviceChange => [$devspec] );
        eval {
		print "Reconfiguring \"" . $vm->name . "\" to add VMDK: \"$fullpath\" ...\n";
        	my $task = $vm->ReconfigVM_Task( spec => $vmspec );
		my $msg = "Sucessfully added VMDK to \"$vmname\"!\n";
                &getStatus($task,$msg);
        };
        if($@) {
        	print "Error: " . $@ . "\n";
        }
}

sub find_datastore {
   my %args = @_;
   my $vm = $args{vm};
   my $dsname = $args{datastore};
   my $host = Vim::get_view(mo_ref => $vm->runtime->host);
   my $datastore = Vim::find_entity_view(
      view_type        => 'Datastore',
      filter   => {
          'summary.name' => qr/$dsname/
       }
   );
   return $datastore;
}

sub find_disk {
   my %args = @_;
   my $vm = $args{vm};
   my $name = $args{fileName};
   my $dsname = $args{datastore};

   my $devices = $vm->config->hardware->device;
   foreach my $device (@$devices) {
        if($device->isa('VirtualDisk')) {
                if($device->backing->isa('VirtualDiskFlatVer2BackingInfo')) {
                        my ($vm_ds,$vmdk_path) = split(']',$device->backing->fileName,2);
                        $vm_ds =~ s/^.//;
                        $vmdk_path =~ s/^.//;
                        my ($vm_dir,$vm_vmdk) = split('/',$vmdk_path,2);
                        return $device if ($vm_vmdk eq $name) && ($vm_ds =~ qr/$dsname/);
                }
        }
   }
   return undef;
}

sub find_device {
   my %args = @_;
   my $vm = $args{vm};
   my $name = $args{controller};

   my $devices = $vm->config->hardware->device;
   foreach my $device (@$devices) {
      return $device if ($device->deviceInfo->label eq $name);
   }
   return undef;
}

sub find_vmdk {
   my %args = @_;
   my $datastore = $args{datastore};
   my $vmdk = $args{file};
   my $browser = Vim::get_view (mo_ref => $datastore->browser);
   my $ds_path = "[" . $datastore->info->name . "]";

   my $disk_flags = VmDiskFileQueryFlags->new(capacityKb => 'true', diskType => 'true', thin => 'false', hardwareVersion => 'false');
   my $detail_query = FileQueryFlags->new(fileOwner => 0, fileSize => 1,fileType => 1,modification => 0);
   my $disk_query = VmDiskFileQuery->new(details => $disk_flags);
   my $searchSpec = HostDatastoreBrowserSearchSpec->new(query => [$disk_query], details => $detail_query);
   my $search_res = $browser->SearchDatastoreSubFolders(datastorePath => $ds_path,searchSpec => $searchSpec);
   foreach my $result (@$search_res) {
      my $files = $result->file;
      my $folder = $result->folderPath;
      foreach my $file (@$files) {
         if(ref($file) eq 'VmDiskFileInfo') {
            my $disk = $file->path;
            my $cap = $file->capacityKb;
            if ($vmdk eq $disk) {
               $fullpath = $folder . $vmdk;
	       return $cap;
            }
         }
      }
   }
   return undef;
}


sub getStatus {
        my ($taskRef,$message) = @_;

        my $task_view = Vim::get_view(mo_ref => $taskRef);
        my $taskinfo = $task_view->info->state->val;
        my $continue = 1;
        while ($continue) {
                my $info = $task_view->info;
                if ($info->state->val eq 'success') {
                        print $message,"\n";
                        return $info->result;
                        $continue = 0;
                } elsif ($info->state->val eq 'error') {
                        my $soap_fault = SoapFault->new;
                        $soap_fault->name($info->error->fault);
                        $soap_fault->detail($info->error->fault);
                        $soap_fault->fault_string($info->error->localizedMessage);
                        die "$soap_fault\n";
                }
                sleep 5;
                $task_view->ViewBase::update_view_data();
        }
}
