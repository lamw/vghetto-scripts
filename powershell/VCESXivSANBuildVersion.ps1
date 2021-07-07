Function Get-VCVersion {
<#
    .NOTES
    ===========================================================================
     Created by:    William Lam
     Organization:  VMware
     Blog:          www.williamlam.com
     Twitter:       @lamw
        ===========================================================================
    .DESCRIPTION
        This function extracts the vCenter Server (Windows or VCSA) build from your env
        and maps it to https://kb.vmware.com/kb/2143838 to retrieve the version and release date
    .EXAMPLE
        Get-VCVersion
#>
    param(
        [Parameter(Mandatory=$false)][VMware.VimAutomation.ViCore.Util10.VersionedObjectImpl]$Server
    )

    # Pulled from https://kb.vmware.com/kb/2143838
    $vcenterBuildVersionMappings = @{
        "16858589"="vCenter Server 7.0 Update 1,2020-10-06"	
		"16764584"="vCenter Server 6.5u3l,2020-08-25"
		"16749670"="vCenter Server 7.0.0d,2020-08-25"
		"16708996"="vCenter Appliance 6.7 Update 3j (6.7.0.45000),2020-08-20"
		"16620013"="vCenter Server 7.0.0c,2020-07-30"
		"16616482"="vCenter Appliance 6.7 Update 3i (6.7.0.44200),2020-07-30"
		"16613358"="vCenter Server 6.5 U3k,2020-07-30"
		"16386335"="vCenter Server 7.0.0b,2020-06-23"	
		"16275304"="vCenter Appliance 6.7 Update 3h (6.7.0.44100),2020-05-28"
		"16275158"="vCenter Server 6.5 U3j,2020-05-28"
		"16189207"="vCenter Server 7.0.0a,2020-05-19"
		"16046470"="vCenter Appliance 6.7 Update 3g (6.7.0.44000),2020-04-28"
		"15976714"="vCenter Appliance 6.7 Update 3f (6.7.0.43000),2020-04-09"
		"15952599"="vCenter Server 7.0 GA,2020-04-02"
		"15808844"="vCenter Appliance 6.7 Update 3e (6.7.0.42300),2020-03-26"
		"15808842"="vCenter Server 6.5 U3i,2020-03-26"
		"15679281"="vCenter Appliance 6.7 Update 3d (6.7.0.42200),2020-02-27"
		"15679215"="vCenter Server 6.5 U3h,2020-02-27"
		"15505668"="vCenter Appliance 6.7 Update 3c (6.7.0.42100),2020-01-30"
		"15505374"="vCenter Server 6.5 U3g,2020-01-30"
		"15259038"="vCenter Server 6.5 U3f,2019-12-19"
		"15132721"="vCenter Appliance 6.7 Update 3b (6.7.0.42000),2019-12-05"
		"15127636"="vCenter Server 6.5 U3e,2019-11-26"
		"14836122"="vCenter Appliance 6.7 Update 3a (6.7.0.41000),2019-10-24"
		"14836121"="vCenter Server 6.5 U3d,2019-10-24"
		"14690228"="vCenter Server 6.5 U3c,2019-09-24"
		"14389939"="vCenter Server 6.5 U3b,2019-08-27"
		"14368073"="vCenter Appliance 6.7 Update 3,2019-08-20"
		"14367737"="vCenter Appliance / vCenter Windows 6.7 Update 3,2019-08-20"
		"14156547"="vCenter Server 6.5 U3a,2019-07-25"
		"14070654"="vCenter Appliance 6.7 Update 2c (6.7.0.32000),2019-07-16"
		"14070457"="vCenter Appliance 6.7 Update 2c (6.7.0.32000),2019-07-16"
		"14020092"="vCenter Server 6.5 U3,2019-07-02"
		"13843469"="vCenter Appliance / vCenter Windows 6.7 Update 2b (6.7.0.31100),2019-05-30 Appliance / 2019-05-14 Windows"
		"13843380"="vCenter Appliance /vCenter Windows 6.7 Update 2b (6.7.0.31100),2019-05-30 Appliance / 2019-05-14 Windows"
		"13834586"="vCenter Server 6.5 U2h,2019-05-30"
		"13643870"="vCenter Appliance / vCenter Windows 6.7 Update 2a (6.7.0.31000),2019-05-14"
		"13639324"="vCenter Appliance 6.7 Update 2a (6.7.0.31000),2019-05-14"
		"13638830"="vCenter Windows 6.7 Update 2a (6.7.0.31000),2019-05-14"
		"13638625"="vCenter Server 6.5 U2g,2019-05-14"
		"13010631"="vCenter Appliance / vCenter Windows 6.7 U2 (6.7.0.30000),2019-04-11"
		"13007421"="vCenter Appliance 6.7 U2 (6.7.0.30000),2019-04-11"
		"13007157"="vCenter Windows 6.7 U2 (6.7.0.30000),2019-04-11"
		"12863991"="vCenter Server 6.5 U2f,2019-03-21"
		"11727113"="vCenter Appliance 6.7 U1b (6.7.0.21000),2019-01-17"
		"11727065"="vCenter Windows 6.7 U1b (6.7.0.21000),2019-01-17"
		"11726888"="vCenter Appliance / vCenter Windows 6.7 U1b (6.7.0.21000),2019-01-17"
		"11347054"="vCenter Server 6.5 U2e,2018-12-20"
		"11338799"="vCenter Appliance 6.7 U1a (6.7.0.20100),2018-12-20"
		"11338176"="vCenter Appliance 6.7 U1a (6.7.0.20100),2018-12-20"	
		"10964411"="vCenter Server 6.5 U2d,2018-11-29"
		"10244857"="vCenter Appliance 6.7 U1 (6.7.0.20000),2018-10-16"
		"10244807"="vCenter Windows 6.7 U1 (6.7.0.20000),2018-10-16"
		"10244745"="vCenter Appliance / vCenter Windows 6.7 U1 (6.7.0.20000),2018-10-16"
		"9451876"="vCenter Appliance / vCenter Windows 6.7d (6.7.0.14000),2018-08-14"
		"9451637"="vCenter Server 6.5 U2c,2018-08-14"
		"9433931"="vCenter Appliance 6.7d (6.7.0.14000),2018-08-14"
		"9433894"="vCenter Windows 6.7d (6.7.0.14000),2018-08-14"
		"9232942"="vCenter Appliance 6.7c (6.7.0.13000),2018-07-26"
		"9232933"="vCenter Windows 6.7c (6.7.0.13000),2018-07-26"
		"9232925"="vCenter Appliance / vCenter Windows 6.7c (6.7.0.13000),2018-07-26"
		"8833179"="vCenter Appliance 6.7b (6.7.0.12000),2018-06-28"
		"8833120"="vCenter Windows 6.7b (6.7.0.12000),2018-06-28"
		"8832884"="vCenter Appliance / vCenter Windows 6.7b (6.7.0.12000),2018-06-28"
		"8815520"="vCenter Server 6.5 U2b,2018-06-28"
		"8546293"="vCenter Appliance 6.7a (6.7.0.11000),2018-05-22"
		"8546281"="vCenter Windows 6.7a (6.7.0.11000),2018-05-22"
		"8546234"="vCenter Appliance / vCenter Windows 6.7a (6.7.0.11000),2018-05-22"
		"8307201"="vCenter Server 6.5 U2,2018-05-03"
		"8217866"="vCenter Appliance / vCenter Windows 6.7 (6.7.0.10000),2018-04-17"
		"8170161"="vCenter Appliance 6.7 (6.7.0.10000),2018-04-17"
		"8170087"="vCenter Windows 6.7 (6.7.0.10000),2018-04-17"
		"8024368"="vCenter Server 6.5 Update 1g,2018-03-20"
		"7515524"="vCenter Server 6.5 Update 1e,2018-01-09"
		"7312210"="vCenter Server 6.5 Update 1d,2017-12-19"
		"6816762"="vCenter Server 6.5 Update 1b,2017-10-26"
		"5973321"="vCenter 6.5 Update 1,2017-07-27"
		"5705665"="vCenter 6.5 0e Express Patch 3,2017-06-15"
		"5326079"="vCenter 6.0 Update 3b,2017-04-13"
		"5318200"="vCenter 6.0 Update 3b,2017-04-13"
		"5318154"="vCenter 6.5 0d Express Patch 2,2017-04-18"
		"5318112"="vCenter 6.5.0c Express Patch 1b,2017-04-13"
		"5183552"="vCenter 6.0 Update 3a,2017-03-21"
		"5183549"="vCenter 6.0 Update 3a,2017-03-21"
		"5178943"="vCenter 6.5.0b,2017-03-14"
		"5112529"="vCenter 6.0 Update 3,2017-02-24"
		"5112527"="vCenter 6.0 Update 3,2017-02-24"
		"4944578"="vCenter 6.5.0a Express Patch 01,2017-02-02"
		"4602587"="vCenter 6.5,2016-11-15"
		"4541948"="vCenter 6.0 Update 2a,2016-11-22"
		"4541947"="vCenter 6.0 Update 2a,2016-11-22"
		"4191365"="vCenter 6.0 Update 2m,2016-09-15"
		"4180648"="vCenter 5.5 Update 3e,2016-08-04"
		"4180647"="vCenter 5.5 Update 3e,2016-08-04"
		"3900744"="vCenter 5.1 Update 3d,2016-05-19"
		"3891028"="vCenter 5.0 U3g,2016-06-14"
		"3891027"="vCenter 5.0 U3g,2016-06-14"
		"3868380"="vCenter 5.1 Update 3d,2016-05-19"
		"3730881"="vCenter 5.5 Update 3d,2016-04-14"
		"3721164"="vCenter 5.5 Update 3d,2016-04-14"
		"3660016"="vCenter 5.5 Update 3c,2016-03-29"
		"3660015"="vCenter 5.5 Update 3c,2016-03-29"
		"3634794"="vCenter 6.0 Update 2,2016-03-15"
		"3634793"="vCenter 6.0 Update 2,2016-03-16"
		"3630963"="vCenter 5.1 Update 3c,2016-03-29"
		"3339084"="vCenter 6.0 Update 1b,2016-01-07"
		"3339083"="vCenter 6.0 Update 1b,2016-01-07"
		"3255668"="vCenter 5.5 Update 3b,2015-12-08"
		"3252642"="vCenter 5.5 Update 3b,2015-12-08"
		"3154314"="vCenter 5.5 Update 3a,2015-10-22"
		"3142196"="vCenter 5.5 Update 3a,2015-10-22"
		"3073237"="vCenter 5.0 U3e,2015-10-01"
		"3073236"="vCenter 5.0 U3e,2015-10-01"
		"3072314"="vCenter 5.1 Update 3b,2015-10-01"
		"3070521"="vCenter 5.1 Update 3b,2015-10-01"
		"3018524"="vCenter 6.0 Update 1,2015-09-10"
		"3018523"="vCenter 6.0 Update 1,2015-09-10"
		"3000347"="vCenter 5.5 Update 3,2015-09-16"
		"3000241"="vCenter 5.5 Update 3,2015-09-16"
		"2776511"="vCenter 6.0.0b,2015-07-07"
		"2776510"="vCenter 6.0.0b,2015-07-07"
		"2669725"="vCenter 5.1 Update 3a,2015-04-30"
		"2656761"="vCenter 6.0.0a,2015-04-16"
		"2656760"="vCenter 6.0.0a,2015-04-16"
		"2656067"="vCenter 5.0 U3d,2015-04-30"
		"2656066"="vCenter 5.0 U3d,2015-04-30"
		"2646489"="vCenter 5.5 Update 2e,2015-04-16"
		"2646482"="vCenter 5.5 Update 2e,2015-04-16"
		"2559268"="vCenter 6.0 GA,2015-03-12"
		"2559267"="vCenter 6.0 GA,2015-03-12"
		"2442329"="vCenter 5.5 Update 2d,2015-01-27"
		"2306353"="vCenter 5.1 Update 3,2014-12-04"
		"2210222"="vCenter 5.0 U3c,2014-11-20"
		"2207772"="vCenter 5.1 Update 2c,2014-10-30"
		"2183111"="vCenter 5.5 Update 2b,2014-10-09"
		"2063318"="vCenter 5.5 Update 2,2014-09-09"
		"2001466"="vCenter 5.5 Update 2,2014-09-09"
		"1945274"="vCenter 5.5 Update 1c,2014-07-22"
		"1917469"="vCenter 5.0 U3a,2014-07-01"
		"1891313"="vCenter 5.5 Update 1b,2014-06-12"
		"1882349"="vCenter 5.1 Update 2a,2014-07-01"
		"1750787"="vCenter 5.5 Update 1a,2014-04-19"
		"1750596"="vCenter 5.5.0c,2014-04-19"
		"1623101"="vCenter 5.5 Update 1,2014-03-11"
		"1623099"="vCenter 5.5 Update 1,2014-03-11"
		"1476327"="vCenter 5.5.0b,2013-12-22"
		"1474364"="vCenter 5.1 Update 2,2014-01-16"
		"1473063"="vCenter 5.1 Update 2,2014-01-16"
		"1398495"="vCenter 5.5.0a,2013-10-31"
		"1378903"="vCenter 5.5.0a,2013-10-31"
		"1364042"="vCenter 5.1 Update 1c,2013-10-17"
		"1364037"="vCenter 5.1 Update 1c,2013-10-17"
		"1312299"="vCenter 5.5 GA,2013-09-22"
		"1312298"="vCenter 5.5 GA,2013-09-22"
		"1302764"="vCenter 5.0 U3,2013-10-17"
		"1300600"="vCenter 5.0 U3,2013-10-17"
		"1235232"="vCenter 5.1 Update 1b,2013-08-01"
		"1123961"="vCenter 5.1 Update 1a,2013-05-22"
		"1065184"="vCenter 5.1 Update 1,2013-04-25"
		"1064983"="vCenter 5.1 Update 1,2013-04-25"
		"947673"="vCenter 5.1.0b,2012-12-20"
		"920217"="vCenter 5.0 U2,2012-12-20"
		"913577"="vCenter 5.0 U2,2012-12-20"
		"880472"="vCenter 5.1.0a,2012-10-25"
		"880146"="vCenter 5.1.0a,2012-10-25"
		"804277"="vCenter 5.0 U1b,2012-08-16"
		"799731"="vCenter 5.1 GA,2012-09-10"
		"799730"="vCenter 5.1 GA,2012-08-13"
		"759855"="vCenter 5.0 U1a,2012-07-12"
		"755629"="vCenter 5.0 U1a,2012-07-12"
		"623373"="vCenter 5.0 U1,2012-03-15"
		"455964"="vCenter 5.0 GA,2011-08-24"
    }

    if(-not $Server) {
        $Server = $global:DefaultVIServer
    }

    $vcBuildNumber = $Server.Build
    $vcName = $Server.Name
    $vcOS = $Server.ExtensionData.Content.About.OsType
    $vcVersion,$vcRelDate = "Unknown","Unknown"

    if($vcenterBuildVersionMappings.ContainsKey($vcBuildNumber)) {
        ($vcVersion,$vcRelDate) = $vcenterBuildVersionMappings[$vcBuildNumber].split(",")
    }

    $tmp = [pscustomobject] @{
        Name = $vcName;
        Build = $vcBuildNumber;
        Version = $vcVersion;
        OS = $vcOS;
        ReleaseDate = $vcRelDate;
    }
    $tmp
}

Function Get-ESXiVersion {
<#
    .NOTES
    ===========================================================================
     Created by:    William Lam
     Organization:  VMware
     Blog:          www.williamlam.com
     Twitter:       @lamw
        ===========================================================================
    .DESCRIPTION
        This function extracts the ESXi build from your env and maps it to
        https://kb.vmware.com/kb/2143832 to extract the version and release date
    .PARAMETER ClusterName
        Name of the vSphere Cluster to retrieve ESXi version information
    .EXAMPLE
        Get-ESXiVersion -ClusterName VSAN-Cluster
#>
    param(
        [Parameter(Mandatory=$false)][String]$ClusterName = "",
        [Parameter(Mandatory=$false)][String]$DatacenterName = ""
    )

    If (($ClusterName -eq "") -and ($DatacenterName -eq "")) {
        Write-Host -ForegroundColor Red "Error: You have to specify a cluster (-ClusterName) or datacenter (-DatacenterName)"
        break
    }

    # Pulled from https://kb.vmware.com/kb/2143832
    $esxiBuildVersionMappings = @{
        "16850804"="ESXi 7.0.1 Update 1,10/6/2020"
        "16713306"="ESXi 6.7 P03,8/20/2020"
        "16576891"="ESXi 6.5 P05,7/30/2020"
        "16389870"="ESXi 6.5 EP 20,6/30/2020"
        "16324942"="ESXi 7.0b,6/23/2020"
        "16316930"="ESXi 6.7 EP 15,6/9/2020"
        "16207673"="ESXi 6.5 EP 19,5/28/2020"
        "16075168"="ESXi 6.7 P02,4/28/2020"
        "15843807"="ESXi 7.0 GA,4/2/2020"
        "15820472"="ESXi 6.7 EP 14,4/7/2020"
        "15517548"="ESXi 6.0 EP 25,2/20/2020"
        "15256549"="ESXi 6.5 P04,12/19/2019"
        "15177306"="ESXi 6.5 EP 18,12/5/2019"
        "15169789"="ESXi 6.0 EP 23,12/5/2019"
        "15160138"="ESXi 6.7 P01,12/5/2019"
        "15018929"="ESXi 6.0 EP 22,11/12/2019"
        "15018017"="ESXi 6.7 EP 13,11/12/2019"
        "14990892"="ESXi 6.5 EP 17,11/12/2019"
        "14874964"="ESXi 6.5 EP 16,10/24/2019"
        "14513180"="ESXi 6.0 P08,9/12/2019"
        "14320405"="ESXi 6.5 EP 15,2019-08-20"
        "14320388"="ESXi 6.7 Update 3,2019-08-20"
        "13981272"="ESXi 6.7 EP 10,2019-06-20"
        "13932383"="ESXi 6.5 Update 3,2019-07-02"
        "13644319"="ESXi 6.7 EP 09,2019-05-14"
        "13635690"="ESXi 6.5 EP 14,2019-05-14"
        "13473784"="ESXi 6.7 EP 08,2019-04-30"
        "13006603"="ESXi 6.7 U2,2019-04-11"
        "13004448"="ESXi 6.7 EP 07,2019-03-28"
        "13004031"="ESXi 6.5 EP 13,2019-03-28"
        "11925212"="ESXi 6.5 EP 12,2019-01-31"
        "11675023"="ESXi 6.7 EP 06,2019-01-17"
        "10884925"="ESXi 6.5 P03,2018-11-29"
        "10764712"="ESXi 6.7 EP 05,2018-11-09"
        "10719125"="ESXi 6.5 EP 11,2018-11-09"
        "10390116"="ESXi 6.5 EP 10,2018-10-23"
        "10302608"="ESXi 6.7 U1,2018-10-16"
        "10176752"="ESXi 6.7 EP 04,2018-10-02"
        "10175896"="ESXi 6.5 EP 09,2018-10-02"
        "9484548"="ESXi 6.7 EP 03,2018-08-14"
        "9298722"="ESXi 6.5 U2C,2018-08-14"
        "9214924"="ESXi 6.7 EP 02a,2018-07-26"
        "8941472"="ESXi 6.7 EP 02,2018-06-28"
        "8935087"="ESXi 6.5 U2b,2018-06-28"
        "8294253"="ESXi 6.5 U2 GA,2018-05-03"
        "8169922"="ESXi 6.7 GA,2018-04-17"
        "7967591"="ESXi 6.5 U1g,2018-03-20"
        "7388607"="ESXi 6.5 Patch 02,2017-12-19"
        "6765664"="ESXi 6.5 U1 Express Patch 4,2017-10-05"
        "5969303"="ESXi 6.5 U1,2017-07-27"
        "5572656"="ESXi 6.0 Patch 5,2017-06-06"
        "5310538"="ESXi 6.5.0d,2017-04-18"
        "5251623"="ESXi 6.0 Express Patch 7c,2017-03-28"
        "5230635"="ESXi 5.5 Express Patch 11,2017-03-28"
        "5224934"="ESXi 6.0 Express Patch 7a,2017-03-28"
        "5224529"="ESXi 6.5 Express Patch 1a,2017-03-28"
        "5146846"="ESXi 6.5 Patch 01,2017-03-09"
        "5050593"="ESXi 6.0 Update 3,2017-02-24"
        "4887370"="ESXi 6.5.0a,2017-02-02"
        "4722766"="ESXi 5.5 Patch 10,2016-12-20"
        "4600944"="ESXi 6.0 Patch 4,2016-11-22"
        "4564106"="ESXi 6.5 GA,2016-11-15"
        "4510822"="ESXi 6.0 Express Patch 7,2016-10-17"
        "4345813"="ESXi 5.5 Patch 9,2016-09-15"
        "4192238"="ESXi 6.0 Patch 3,2016-08-04"
        "4179633"="ESXi 5.5 Patch 8,2016-08-04"
        "3982828"="ESXi 5.0 Patch 13,2016-06-14"
        "3872664"="ESXi 5.1 Patch 9,2016-05-24"
        "3825889"="ESXi 6.0 Express Patch 6,2016-05-12"
        "3620759"="ESXi 6.0 Update 2,2016-03-16"
        "3568940"="ESXi 6.0 Express Patch 5,2016-02-23"
        "3568722"="ESXi 5.5 Express Patch 10,2016-02-22"
        "3380124"="ESXi 6.0 Update 1b,2016-01-07"
        "3343343"="ESXi 5.5 Express Patch 9,2016-01-04"
        "3248547"="ESXi 5.5 Update 3b,2015-12-08"
        "3247720"="ESXi 6.0 Express Patch 4,2015-11-25"
        "3116895"="ESXi 5.5 Update 3a,2015-10-06"
        "3086167"="ESXi 5.0 Patch 12,2015-10-01"
        "3073146"="ESXi 6.0 U1a Express Patch 3,2015-10-06"
        "3070626"="ESXi 5.1 Patch 8,2015-10-01"
        "3029944"="ESXi 5.5 Update 3,2015-09-16"
        "3029758"="ESXi 6.0 U1,2015-09-10"
        "2809209"="ESXi 6.0.0b,2015-07-07"
        "2718055"="ESXi 5.5 Patch 5,2015-05-08"
        "2715440"="ESXi 6.0 Express Patch 2,2015-05-14"
        "2638301"="ESXi 5.5 Express Patch 7,2015-04-07"
        "2615704"="ESXi 6.0 Express Patch 1,2015-04-09"
        "2583090"="ESXi 5.1 Patch 7,2015-03-26"
        "2509828"="ESXi 5.0 Patch 11,2015-02-24"
        "2494585"="ESXi 6.0 GA,2015-03-12"
        "2456374"="ESXi 5.5 Express Patch 6,2015-02-05"
        "2403361"="ESXi 5.5 Patch 4,2015-01-27"
        "2323236"="ESXi 5.1 Update 3,2014-12-04"
        "2312428"="ESXi 5.0 Patch 10,2014-12-04"
        "2302651"="ESXi 5.5 Express Patch 5,2014-12-02"
        "2191751"="ESXi 5.1 Patch 6,2014-10-30"
        "2143827"="ESXi 5.5 Patch 3,2014-10-15"
        "2068190"="ESXi 5.5 Update 2,2014-09-09"
        "2000308"="ESXi 5.0 Patch 9,2014-08-28"
        "2000251"="ESXi 5.1 Patch 5,2014-07-31"
        "1918656"="ESXi 5.0 Express Patch 6,2014-07-01"
        "1900470"="ESXi 5.1 Express Patch 5,2014-06-17"
        "1892794"="ESXi 5.5 Patch 2,2014-07-01"
        "1881737"="ESXi 5.5 Express Patch 4,2014-06-11"
        "1851670"="ESXi 5.0 Patch 8,2014-05-29"
        "1746974"="ESXi 5.5 Express Patch 3,2014-04-19"
        "1746018"="ESXi 5.5 Update 1a,2014-04-19"
        "1743533"="ESXi 5.1 Patch 4,2014-04-29"
        "1623387"="ESXi 5.5 Update 1,2014-03-11"
        "1612806"="ESXi 5.1 Express Patch 4,2014-02-27"
        "1489271"="ESXi 5.0 Patch 7,2014-01-23"
        "1483097"="ESXi 5.1 Update 2,2014-01-16"
        "1474528"="ESXi 5.5 Patch 1,2013-12-22"
        "1331820"="ESXi 5.5 GA,2013-09-22"
        "1312873"="ESXi 5.1 Patch 3,2013-10-17"
        "1311175"="ESXi 5.0 Update 3,2013-10-17"
        "1254542"="ESXi 5.0 Patch 6,2013-08-29"
        "1157734"="ESXi 5.1 Patch 2,2013-07-25"
        "1117900"="ESXi 5.1 Express Patch 3,2013-05-23"
        "1117897"="ESXi 5.0 Express Patch 5,2013-05-15"
        "1065491"="ESXi 5.1 Update 1,2013-04-25"
        "1024429"="ESXi 5.0 Patch 5,2013-03-28"
        "1021289"="ESXi 5.1 Express Patch 2,2013-03-07"
        "914609"="ESXi 5.1 Patch 1,2012-12-20"
        "914586"="ESXi 5.0 Update 2,2012-12-20"
        "838463"="ESXi 5.1.0a,2012-10-25"
        "821926"="ESXi 5.0 Patch 4,2012-09-27"
        "799733"="ESXi 5.1.0 GA,2012-09-10"
        "768111"="ESXi 5.0 Patch 3,2012-07-12"
        "721882"="ESXi 5.0 Express Patch 4,2012-06-14"
        "702118"="ESXi 5.0 Express Patch 3,2012-05-03"
        "653509"="ESXi 5.0 Express Patch 2,2012-04-12"
        "623860"="ESXi 5.0 Update 1,2012-03-15"
        "515841"="ESXi 5.0 Patch 2,2011-12-15"
        "504890"="ESXi 5.0 Express Patch 1,2011-11-03"
        "474610"="ESXi 5.0 Patch 1,2011-09-13"
        "469512"="ESXi 5.0 GA,2011-08-24"
        
    }

    $vmhosts = @()
    If($ClusterName -ne "") {
        
        $cluster = Get-Cluster -Name $ClusterName -ErrorAction SilentlyContinue
        
        if($cluster -eq $null) {
            Write-Host -ForegroundColor Red "Error: Unable to find vSAN Cluster $ClusterName ..."
            break
        } Else {
            $vmhosts = $cluster.ExtensionData.Host
        }
    } Else {

        If($DatacenterName -ne "") {
    
            $datacenter = Get-Datacenter -Name $DatacenterName -ErrorAction SilentlyContinue

            If($datacenter -eq $null) {
                Write-Host -ForegroundColor Red "Error: Unable to find Datacenter $DatacenterName ..."
                break
            } Else {
                $vmhosts = $datacenter | Get-VMHost
            }
        }
    }

    $results = @()
    foreach ($vmhost in $vmhosts) {
        $vmhost_view = Get-View $vmhost -Property Name, Config, ConfigManager.ImageConfigManager

        $esxiName = $vmhost_view.name
        $esxiBuild = $vmhost_view.Config.Product.Build
        $esxiVersionNumber = $vmhost_view.Config.Product.Version
        $esxiVersion,$esxiRelDate,$esxiOrigInstallDate = "Unknown","Unknown","N/A"

        if($esxiBuildVersionMappings.ContainsKey($esxiBuild)) {
            ($esxiVersion,$esxiRelDate) = $esxiBuildVersionMappings[$esxiBuild].split(",")
        }

        # Install Date API was only added in 6.5
        if($esxiVersionNumber -eq "6.5.0") {
            $imageMgr = Get-View $vmhost_view.ConfigManager.ImageConfigManager
            $esxiOrigInstallDate = $imageMgr.installDate()
        }

        $tmp = [pscustomobject] @{
            Name = $esxiName;
            Build = $esxiBuild;
            Version = $esxiVersion;
            ReleaseDate = $esxiRelDate;
            OriginalInstallDate = $esxiOrigInstallDate;
        }
        $results+=$tmp
    }
    $results
}

Function Get-VSANVersion {
<#
    .NOTES
    ===========================================================================
     Created by:    William Lam
     Organization:  VMware
     Blog:          www.williamlam.com
     Twitter:       @lamw
        ===========================================================================
    .DESCRIPTION
        This function extracts the ESXi build from your env and maps it to
        https://kb.vmware.com/kb/2150753 to extract the vSAN version and release date
    .PARAMETER ClusterName
        Name of a vSAN Cluster to retrieve vSAN version information
    .EXAMPLE
        Get-VSANVersion -ClusterName VSAN-Cluster
#>
    param(
        [Parameter(Mandatory=$true)][String]$ClusterName
    )

    # Pulled from https://kb.vmware.com/kb/2150753
        $vsanBuildVersionMappings = @{
            "13981272"="vSAN 6.7 Update 3 / vSAN 6.7 Express Patch 10,ESXi 6.7 Update 3 / ESXi 6.7 Express Patch 10,2019-08-20 (Update 3) / 2019-06-20 (Express Patch 10)"
            "13644319"="vSAN 6.7 Express Patch 09,ESXi 6.7 Express Patch 09,2019-05-14"
            "13473784"="vSAN 6.7 Express Patch 08,ESXi 6.7 Express Patch 08,2019-04-30"
            "13006603"="vSAN 6.7 Update 2,ESXi 6.7 Update 2,2019-04-11"
            "13004448"="vSAN 6.7 Express Patch 07,ESXi 6.7 Express Patch 07,2019-03-28"
            "11675023"="vSAN 6.7 Express Patch 06,ESXi 6.7 Express Patch 06,2019-01-17"
            "10764712"="vSAN 6.7 Express Patch 05,ESXi 6.7 Express Patch 05,2018-11-09"
            "10302608"="vSAN 6.7 Update 1,ESXi 6.7 Update 1,2018-10-17"
            "10176752"="vSAN 6.7 Express Patch 4,ESXi 6.7 Express Patch 4,2018-10-02"
            "8169922"="vSAN 6.7 GA,ESXi 6.7 GA,2018-04-17"
            "14320405"="vSAN 6.6.1 Express Patch 15,ESXi 6.5 Express Patch 15,2019-08-20"
            "13932383"="vSAN 6.6.1 Update 3,ESXi 6.5 Update 3,2019-07-02"
            "13635690"="vSAN 6.6.1 Express Patch 14,ESXi 6.5 Express Patch 14,2019-05-14"
            "13004031"="vSAN 6.6.1 Express Patch 13,ESXi 6.5 Express Patch 13,2019-03-28"
            "11925212"="vSAN 6.6.1 Express Patch 12,ESXi 6.5 Express Patch 12,2019-01-31"
            "10719125"="vSAN 6.6.1 Express Patch 11,ESXi 6.5 Express Patch 11,2018-09-11"
            "10390116"="vSAN 6.6.1 Express Patch 10,ESXi 6.5 Express Patch 10,2018-10-23"
            "10175896"="vSAN 6.6.1 Express Patch 9,ESXi 6.5 Express Patch 9,2018-10-02"
            "8294253"="vSAN 6.6.1 Update 2,ESXi 6.5 U2,2018-05-03"
            "10884925"="vSAN 6.6.1 Patch 03,ESXi 6.5 Patch 03,2018-11-29"
            "7388607"="vSAN 6.6.1 Patch 02,ESXi 6.5 Patch 02,2017-12-19"
            "6765664"="vSAN 6.6.1 Express Patch 4,ESXi 6.5 Express Patch 4,2017-10-05"
            "5969303"="vSAN 6.6.1,ESXi 6.5 Update 1,2017-07-27"
            "5310538"="vSAN 6.6,ESXi 6.5.0d,2017-04-18"
            "5224529"="vSAN 6.5 Express Patch 1a,ESXi 6.5 Express Patch 1a,2017-03-28"
            "5146846"="vSAN 6.5 Patch 01,ESXi 6.5 Patch 01,2017-03-09"
            "4887370"="vSAN 6.5.0a,ESXi 6.5.0a,2017-02-02"
            "4564106"="vSAN 6.5,ESXi 6.5 GA,2016-11-15"
            "5572656"="vSAN 6.2 Patch 5,ESXi 6.0 Patch 5,2017-06-06"
            "5251623"="vSAN 6.2 Express Patch 7c,ESXi 6.0 Express Patch 7c,2017-03-28"
            "5224934"="vSAN 6.2 Express Patch 7a,ESXi 6.0 Express Patch 7a,2017-03-28"
            "5050593"="vSAN 6.2 Update 3,ESXi 6.0 Update 3,2017-02-24"
            "4600944"="vSAN 6.2 Patch 4,ESXi 6.0 Patch 4,2016-11-22"
            "4510822"="vSAN 6.2 Express Patch 7,ESXi 6.0 Express Patch 7,2016-10-17"
            "4192238"="vSAN 6.2 Patch 3,ESXi 6.0 Patch 3,2016-08-04"
            "3825889"="vSAN 6.2 Express Patch 6,ESXi 6.0 Express Patch 6,2016-05-12"
            "3620759"="vSAN 6.2,ESXi 6.0 Update 2,2016-03-16"
            "3568940"="vSAN 6.1 Express Patch 5,ESXi 6.0 Express Patch 5,2016-02-23"
            "3380124"="vSAN 6.1 Update 1b,ESXi 6.0 Update 1b,2016-01-07"
            "3247720"="vSAN 6.1 Express Patch 4,ESXi 6.0 Express Patch 4,2015-11-25"
            "3073146"="vSAN 6.1 U1a (Express Patch 3),ESXi 6.0 U1a (Express Patch 3),2015-10-06"
            "3029758"="vSAN 6.1,ESXi 6.0 U1,2015-09-10"
            "2809209"="vSAN 6.0.0b,ESXi 6.0.0b,2015-07-07"
            "2715440"="vSAN 6.0 Express Patch 2,ESXi 6.0 Express Patch 2,2015-05-14"
            "2615704"="vSAN 6.0 Express Patch 1,ESXi 6.0 Express Patch 1,2015-04-09"
            "2494585"="vSAN 6.0,ESXi 6.0 GA,2015-03-12"
            "5230635"="vSAN 5.5 Express Patch 11,ESXi 5.5 Express Patch 11,2017-03-28"
            "4722766"="vSAN 5.5 Patch 10,ESXi 5.5 Patch 10,2016-12-20"
            "4345813"="vSAN 5.5 Patch 9,ESXi 5.5 Patch 9,2016-09-15"
            "4179633"="vSAN 5.5 Patch 8,ESXi 5.5 Patch 8,2016-08-04"
            "3568722"="vSAN 5.5 Express Patch 10,ESXi 5.5 Express Patch 10,2016-02-22"
            "3343343"="vSAN 5.5 Express Patch 9,ESXi 5.5 Express Patch 9,2016-01-04"
            "3248547"="vSAN 5.5 Update 3b,ESXi 5.5 Update 3b,2015-12-08"
            "3116895"="vSAN 5.5 Update 3a,ESXi 5.5 Update 3a,2015-10-06"
            "3029944"="vSAN 5.5 Update 3,ESXi 5.5 Update 3,2015-09-16"
            "2718055"="vSAN 5.5 Patch 5,ESXi 5.5 Patch 5,2015-05-08"
            "2638301"="vSAN 5.5 Express Patch 7,ESXi 5.5 Express Patch 7,2015-04-07"
            "2456374"="vSAN 5.5 Express Patch 6,ESXi 5.5 Express Patch 6,2015-02-05"
            "2403361"="vSAN 5.5 Patch 4,ESXi 5.5 Patch 4,2015-01-27"
            "2302651"="vSAN 5.5 Express Patch 5,ESXi 5.5 Express Patch 5,2014-12-02"
            "2143827"="vSAN 5.5 Patch 3,ESXi 5.5 Patch 3,2014-10-15"
            "2068190"="vSAN 5.5 Update 2,ESXi 5.5 Update 2,2014-09-09"
            "1892794"="vSAN 5.5 Patch 2,ESXi 5.5 Patch 2,2014-07-01"
            "1881737"="vSAN 5.5 Express Patch 4,ESXi 5.5 Express Patch 4,2014-06-11"
            "1746018"="vSAN 5.5 Update 1a,ESXi 5.5 Update 1a,2014-04-19"
            "1746974"="vSAN 5.5 Express Patch 3,ESXi 5.5 Express Patch 3,2014-04-19"
            "1623387"="vSAN 5.5,ESXi 5.5 Update 1,2014-03-11"
        }

    $cluster = Get-Cluster -Name $ClusterName -ErrorAction SilentlyContinue
    if($cluster -eq $null) {
        Write-Host -ForegroundColor Red "Error: Unable to find vSAN Cluster $ClusterName ..."
        break
    }

    $results = @()
    foreach ($vmhost in $cluster.ExtensionData.Host) {
        $vmhost_view = Get-View $vmhost -Property Name, Config, ConfigManager.ImageConfigManager

        $esxiName = $vmhost_view.name
        $esxiBuild = $vmhost_view.Config.Product.Build
        $esxiVersionNumber = $vmhost_view.Config.Product.Version
        $vsanVersion,$esxiVersion,$esxiRelDate = "Unknown","Unknown","Unknown"

        # Technically as of vSAN 6.2 Mgmt API, this information is already built in natively within
        # the product to retrieve ESXi/VC/vSAN Versions
        # See https://github.com/lamw/vghetto-scripts/blob/master/powershell/VSANVersion.ps1
        if($vsanBuildVersionMappings.ContainsKey($esxiBuild)) {
            ($vsanVersion,$esxiVersion,$esxiRelDate) = $vsanBuildVersionMappings[$esxiBuild].split(",")
        }

        $tmp = [pscustomobject] @{
            Name = $esxiName;
            Build = $esxiBuild;
            VSANVersion = $vsanVersion;
            ESXiVersion = $esxiVersion;
            ReleaseDate = $esxiRelDate;
        }
        $results+=$tmp
    }
    $results
}
