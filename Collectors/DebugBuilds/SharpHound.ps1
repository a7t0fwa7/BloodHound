function Invoke-BloodHound
{
    <#
    .SYNOPSIS

        Runs the BloodHound C# Ingestor using reflection. The assembly is stored in this file.

    .DESCRIPTION

        Using reflection and assembly.load, load the compiled BloodHound C# ingestor into memory
        and run it without touching disk. Parameters are converted to the equivalent CLI arguments
        for the SharpHound executable and passed in via reflection. The appropriate function
        calls are made in order to ensure that assembly dependencies are loaded properly.

    .PARAMETER CollectionMethod

        Specifies the CollectionMethod being used. Possible value are:
            Group - Collect group membership information
            LocalGroup - Collect local group information for computers
            LocalAdmin - Collect local admin users for computers
            RDP - Collect remote desktop users for computers
            DCOM - Collect distributed COM users for computers
            PSRemote - Collected members of the Remote Management Users group for computers
            Session - Collect session information for computers
            Trusts - Enumerate domain trust data
            ACL - Collect ACL (Access Control List) data
            Container - Collect GPO/OU Data
            ComputerOnly - Collects Local Group and Session data
            GPOLocalGroup - Collects Local Group information using GPO (Group Policy Objects)
            LoggedOn - Collects session information using privileged methods (needs admin!)
            ObjectProps - Collects node property information for users and computers
            SPNTargets - Collects SPN targets (currently only MSSQL)
            Default - Collects Group Membership, Local Admin, Sessions, Containers, ACLs and Domain Trusts
            DcOnly - Collects Group Membership, ACLs, ObjectProps, Trusts, Containers, and GPO Admins
            All - Collect all data

        This can be a list of comma seperated valued as well to run multiple collection methods!
        
    .PARAMETER Domain
    
        Specifies the domain to enumerate. If not specified, will enumerate the current
        domain your user context specifies.

    .PARAMETER SearchForest
            
        Search all trusted domains in the forest. 

    .PARAMETER Stealth

        Use stealth collection options, will sacrifice data quality in favor of much reduced
        network impact

    .PARAMETER LdapFilter
    
        Append this ldap filter to the search filter to further filter the results enumerated
            
    .PARAMETER DistinguishedName
    
        DistinguishedName to start LDAP searches at. Equivalent to the old -Ou option
            
    .PARAMETER ComputerFile
    
        A file containing a list of computers to enumerate. This option can only be used with the following Collection Methods:
        Session, Session, LocalGroup, ComputerOnly, LoggedOn
            
    .PARAMETER OutputDirectory
    
        Folder to output files too
    
    .PARAMETER OutputPrefix

        Prefix to add to output files
        
    .PARAMETER CacheName
    
        Name for the cache file dropped to disk (default: unique hash generated per machine)
            
    .PARAMETER MemCache
    
        Don't write the cache file to disk. Caching will still be performed in memory.
            
    .PARAMETER RebuildCache
    
        Invalidate and rebuild the cache file
            
    .PARAMETER RandomFileNames
    
        Randomize file names completely
            
    .PARAMETER ZipFilename
    
        Name for the zip file output by data collection
            
    .PARAMETER NoZip
    
        Do NOT zip the json files
            
    .PARAMETER ZipPassword
    
        Encrypt the zip file with the specified password
            
    .PARAMETER TrackComputerCalls
    
        Write a CSV file with the results of each computer API call to disk
            
    .PARAMETER PrettyPrint
    
        Output "pretty" json with formatting for readability

    
    .PARAMETER LdapUsername
    
        Username for connecting to LDAP. Use this if you're using a non-domain account for connecting to computers
    
    .PARAMETER LdapPassword

        Password for connecting to LDAP. Use this if you're using a non-domain account for connecting to computers
    

    .PARAMETER DomainController

        Domain Controller to connect too. Specifiying this can result in data loss

    .PARAMETER LdapPort

        Port LDAP is running on. Defaults to 389/686 for LDAPS

    .PARAMETER SecureLDAP

        Connect to LDAPS (LDAP SSL) instead of regular LDAP
        
    .PARAMETER DisableCertVerification
        
        Disable certificate verification for secure LDAP

    .PARAMETER DisableSigning

        Disables keberos signing/sealing, making LDAP traffic viewable

    .PARAMETER SkipPortCheck

        Skip SMB port checks when connecting to computers
        
    .PARAMETER PortScanTimeout
    
        Timeout for port checks
        
    .PARAMETER SkipPasswordCheck
    
        Skip checking of PwdLastSet time for computer scanning
        
    .PARAMETER ExcludeDCs
    
        Exclude domain controllers from enumeration (usefult o avoid Microsoft ATP/ATA)

    .PARAMETER Throttle

        Throttle requests to computers (in milliseconds)

    .PARAMETER Jitter

        Add jitter to throttle
        
    .PARAMETER Threads
    
        Number of threads to run enumeration with (Default: 50)
        
    .PARAMETER SkipRegistryLoggedOn
    
        Disable remote registry check in LoggedOn collection
        
    .PARAMETER OverrideUserName

        Override username to filter for NetSessionEnum

    .PARAMETER RealDNSName

        Overrides the DNS name used for API calls

    .PARAMETER CollectAllProperties

        Collect all string LDAP properties on objects
        
    .PARAMETER Loop
    
        Perform looping for computer collection
    
    .PARAMETER LoopDuration

        Duration to perform looping (Default 02:00:00)

    .PARAMETER LoopInterval

        Interval to sleep between loops (Default 00:05:00)

    .PARAMETER StatusInterval

        Interval for displaying status in milliseconds

    .PARAMETER Verbosity

        Change verbosity of output. Default 2 (lower is more)

    .PARAMETER Help

        Display this help screen

    .PARAMETER Version

        Display version information

    .EXAMPLE

        PS C:\> Invoke-BloodHound

        Executes the default collection options and exports JSONs to the current directory, compresses the data to a zip file,
        and then removes the JSON files from disk

    .EXAMPLE

        PS C:\> Invoke-BloodHound -Loop -LoopInterval 00:01:00 -LoopDuration 00:10:00

        Executes session collection in a loop. Will wait 1 minute after each run to continue collection
        and will continue running for 10 minutes after which the script will exit

    .EXAMPLE

        PS C:\> Invoke-BloodHound -CollectionMethod All

        Runs ACL, ObjectProps, Container, and Default collection methods, compresses the data to a zip file,
        and then removes the JSON files from disk

    .EXAMPLE

        PS C:\> Invoke-BloodHound -CollectionMethod DCOnly -NoSaveCache -RandomizeFilenames -EncryptZip

        (Opsec!) Run LDAP only collection methods (Groups, Trusts, ObjectProps, ACL, Containers, GPO Admins) without outputting the cache file to disk.
        Randomizes filenames of the JSON files and the zip file and adds a password to the zip file
    #>

    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Alias("c")]
        [String[]]
        $CollectionMethod = [String[]]@('Default'),

        [Alias("d")]
        [String]
        $Domain,
        
        [Alias("s")]
        [Switch]
        $SearchForest,

        [Switch]
        $Stealth,

        [String]
        $LdapFilter,

        [String]
        $DistinguishedName,

        [String]
        $ComputerFile,

        [ValidateScript({ Test-Path -Path $_ })]
        [String]
        $OutputDirectory = $( Get-Location ),

        [ValidateNotNullOrEmpty()]
        [String]
        $OutputPrefix,

        [String]
        $CacheName,

        [Switch]
        $MemCache,

        [Switch]
        $RebuildCache,

        [Switch]
        $RandomFilenames,

        [String]
        $ZipFilename,
        
        [Switch]
        $NoZip,
        
        [String]
        $ZipPassword,
        
        [Switch]
        $TrackComputerCalls,
        
        [Switch]
        $PrettyPrint,

        [String]
        $LdapUsername,

        [String]
        $LdapPassword,

        [string]
        $DomainController,

        [ValidateRange(0, 65535)]
        [Int]
        $LdapPort,

        [Switch]
        $SecureLdap,
        
        [Switch]
        $DisableCertVerification,

        [Switch]
        $DisableSigning,

        [Switch]
        $SkipPortCheck,

        [ValidateRange(50, 5000)]
        [Int]
        $PortCheckTimeout = 500,

        [Switch]
        $SkipPasswordCheck,

        [Switch]
        $ExcludeDCs,

        [Int]
        $Throttle,

        [ValidateRange(0, 100)]
        [Int]
        $Jitter,

        [Int]
        $Threads,

        [Switch]
        $SkipRegistryLoggedOn,

        [String]
        $OverrideUsername,

        [String]
        $RealDNSName,

        [Switch]
        $CollectAllProperties,

        [Switch]
        $Loop,

        [String]
        $LoopDuration,

        [String]
        $LoopInterval,

        [ValidateRange(500, 60000)]
        [Int]
        $StatusInterval,
        
        [Alias("v")]
        [ValidateRange(0, 5)]
        [Int]
        $Verbosity,

        [Alias("h")]
        [Switch]
        $Help,

        [Switch]
        $Version
    )

    $vars = New-Object System.Collections.Generic.List[System.Object]

    if ($CollectionMethod)
    {
        $vars.Add("--CollectionMethods");
        foreach ($cmethod in $CollectionMethod)
        {
            $vars.Add($cmethod);
        }
    }

    if ($Domain)
    {
        $vars.Add("--Domain");
        $vars.Add($Domain);
    }
    
    if ($SearchForest)
    {
        $vars.Add("--SearchForest")    
    }

    if ($Stealth)
    {
        $vars.Add("--Stealth")
    }

    if ($LdapFilter)
    {
        $vars.Add("--LdapFilter");
        $vars.Add($LdapFilter);
    }

    if ($DistinguishedName)
    {
        $vars.Add("--DistinguishedName")
        $vars.Add($DistinguishedName)
    }
    
    if ($ComputerFile)
    {
        $vars.Add("--ComputerFile");
        $vars.Add($ComputerFile);
    }

    if ($OutputDirectory)
    {
        $vars.Add("--OutputDirectory");
        $vars.Add($OutputDirectory);
    }

    if ($OutputPrefix)
    {
        $vars.Add("--OutputPrefix");
        $vars.Add($OutputPrefix);
    }

    if ($CacheName)
    {
        $vars.Add("--CacheName");
        $vars.Add($CacheName);
    }

    if ($NoSaveCache)
    {
        $vars.Add("--MemCache");
    }

    if ($RebuildCache)
    {
        $vars.Add("--RebuildCache");
    }

    if ($RandomFilenames)
    {
        $vars.Add("--RandomFilenames");
    }

    if ($ZipFileName)
    {
        $vars.Add("--ZipFileName");
        $vars.Add($ZipFileName);
    }

    if ($NoZip)
    {
        $vars.Add("--NoZip");
    }

    if ($ZipPassword)
    {
        $vars.Add("--ZipPassword");
        $vars.Add($ZipPassword)
    }

    if ($TrackComputerCalls)
    {
        $vars.Add("--TrackComputerCalls")
    }

    if ($PrettyPrint)
    {
        $vars.Add("--PrettyPrint");
    }

    if ($LdapUsername)
    {
        $vars.Add("--LdapUsername");
        $vars.Add($LdapUsername);
    }

    if ($LdapPassword)
    {
        $vars.Add("--LdapPassword");
        $vars.Add($LdapPassword);
    }

    if ($DomainController)
    {
        $vars.Add("--DomainController");
        $vars.Add($DomainController);
    }
    
    if ($LdapPort)
    {
        $vars.Add("--LdapPort");
        $vars.Add($LdapPort);
    }
    
    if ($SecureLdap)
    {
        $vars.Add("--SecureLdap");
    }
    
    if ($DisableCertVerification) 
    {
        $vars.Add("--DisableCertVerification")    
    }

    if ($DisableSigning)
    {
        $vars.Add("--DisableSigning");
    }

    if ($SkipPortCheck)
    {
        $vars.Add("--SkipPortCheck");
    }

    if ($PortCheckTimeout)
    {
        $vars.Add("--PortCheckTimeout")
        $vars.Add($PortCheckTimeout)
    }

    if ($SkipPasswordCheck)
    {
        $vars.Add("--SkipPasswordCheck");
    }

    if ($ExcludeDCs)
    {
        $vars.Add("--ExcludeDCs")
    }

    if ($Throttle)
    {
        $vars.Add("--Throttle");
        $vars.Add($Throttle);
    }

    if ($Jitter -gt 0)
    {
        $vars.Add("--Jitter");
        $vars.Add($Jitter);
    }
    
    if ($Threads)
    {
        $vars.Add("--Threads")
        $vars.Add($Threads)
    }

    if ($SkipRegistryLoggedOn)
    {
        $vars.Add("--SkipRegistryLoggedOn")
    }

    if ($OverrideUserName)
    {
        $vars.Add("--OverrideUserName")
        $vars.Add($OverrideUsername)
    }
    
    if ($RealDNSName)
    {
        $vars.Add("--RealDNSName")
        $vars.Add($RealDNSName)
    }

    if ($CollectAllProperties)
    {
        $vars.Add("--CollectAllProperties")
    }

    if ($Loop)
    {
        $vars.Add("--Loop")
    }

    if ($LoopDuration)
    {
        $vars.Add("--LoopDuration")
        $vars.Add($LoopDuration)
    }

    if ($LoopInterval)
    {
        $vars.Add("--LoopInterval")
        $vars.Add($LoopInterval)
    }

    if ($StatusInterval)
    {
        $vars.Add("--StatusInterval")
        $vars.Add($StatusInterval)
    }

    if ($Verbosity)
    {
        $vars.Add("-v");
        $vars.Add($Verbosity);
    }    

    if ($Help)
    {
        $vars.clear()
        $vars.Add("--Help");
    }

    if ($Version)
    {
        $vars.clear();
        $vars.Add("--Version");
    }

    $passed = [string[]]$vars.ToArray()


	$DeflatedStream = New-Object IO.Compression.DeflateStream([IO.MemoryStream][Convert]::FromBase64String($EncodedCompressedFile),[IO.Compression.CompressionMode]::Decompress)
	$UncompressedFileBytes = New-Object Byte[](917504)
	$DeflatedStream.Read($UncompressedFileBytes, 0, 917504) | Out-Null
	$Assembly = [Reflection.Assembly]::Load($UncompressedFileBytes)
	$BindingFlags = [Reflection.BindingFlags] "Public,Static"
	$a = @()
	$Assembly.GetType("Costura.AssemblyLoader", $false).GetMethod("Attach", $BindingFlags).Invoke($Null, @())
	$Assembly.GetType("Sharphound.Program").GetMethod("InvokeSharpHound").Invoke($Null, @(,$passed))
}