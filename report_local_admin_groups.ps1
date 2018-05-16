$search_base = "DC=subdomain,DC=domain,DC=com"
$localadmin_groups = get-adgroup -ldapfilter "(&(objectCategory=group)(cn=*localadmins*)(!(cn=*computers*)))" -searchbase $search_base
$records = @{}

foreach ($group_name in $localadmin_groups)
{
	$group_desc = get-adgroup -identity $group_name.name -property description | select description
	$group_members = get-adgroupmember -identity $group_name.name -recursive  

	$records.add($group_name.name, @{"description" = $group_desc; "members" = @(); "computers" = @()})

    foreach ($group_member in $group_members)
    {
        if ($group_member.objectClass -eq "user")
        {
            $user_info = get-aduser -identity $group_member.name -properties lastlogondate | select name, lastlogondate
            
            # If members is not null, add member to the object.
            if (!$records.get_item($group_name.name).get_item("members"))
            {   
                $records.($group_name.name)."members" = @(@{"username" = $user_info.name; "lastlogondate" = $user_info.lastlogondate})
                
            } else {
                $records.($group_name.name)."members" += @{"username" =  $user_info.name; "lastlogondate" = $user_info.lastlogondate}
                
            }                    
        }
    }
}

# Attempt to enumerate the associated group_name_computers
$localadmincomp_groups = get-adgroup -ldapfilter "(&(objectCategory=group)(cn=*localadmin*)(cn=*computers*))" -searchbase $search_base

foreach ($record in $records.GetEnumerator())
{
    foreach ($localadmincomp_group in $localadmincomp_groups)
    {
        $group_name_computers_stripped = ($localadmincomp_group.name).Replace("Computers", "").replace("computers", "").replace("Admins", "Admin").replace("admins", "admin") + "s"
        if ($record.name -eq $group_name_computers_stripped)
        {
            $computers = get-adgroupmember -identity $localadmincomp_group.name -recursive | select name
            try 
            {
                $record.value."computers" = $computers
            } 
            catch [System.Management.Automation.RuntimeException] 
            {
                write-host $record.name
                write-host $_
            }
        }
    }
}

# Unwrap $records hash table for reporting
$line = ""
foreach ($record in $records.GetEnumerator())
{
    $group_name = $record.name
    $group_description = ($record.value).get_item("description").description
    $members_count = (($record.value).get_item("members")).count
    if ($members_count -gt 0)
    {
        $members_csv = (((($record.value).get_item("members") | foreach-object{ [pscustomobject]$_ } | ConvertTo-Csv -notypeinformation)[1..(($record.value).get_item("members").count)]).replace('"', "").replace("'", "") -join "`r`n" ) 
    }
    $computers_count = (($record.value).get_item("computers")).count
    if ($computers_count -gt 0)
    {
        $computers_csv = ((($record.value).get_item("computers") | foreach-object{ [pscustomobject]$_ } | convertto-csv -notypeinformation)[1..$computers_count].replace('"', "") -join "`r`n")
    }

    $line +=  '"{0}","{1}","{2}","{3}"' -f $group_name, $group_description, $members_csv, $computers_csv + "`n"
}

$header = 'sep=,'+"`n"+'"group_name","group_description","members","computers"' + "`n"
$header + $line | out-file "C:\temp\file.csv"
