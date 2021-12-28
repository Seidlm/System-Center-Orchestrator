
# Details of the runbook we are going to run
#See BlogPost for Details: https://www.techguy.at/sql-query-to-get-runbook-and-parameter-id-from-sql-system-center-orchestrator/
$RunbookID = "d42b9286-1c37-4788-8026-1e53b5bf547c"  
$rbParameters = @{
"6c6b4f0f-5f55-4181-8a13-223f40483922" = "sdfs"  # Parameter 1
}	

#SCO WebServer Name
$SCOServer="viepaps34"

#Some Setting
$WaitToCompleteRunbook=$True
$IncludePendingTimeToExecutionTime=$false
[int]$CheckIntervallInSeconds=5
[int]$MaxExecutionTimeInSeconds=60

function GetScorchProperty([System.Object]$XMLString, [string]$Name, [string]$Direction, [string]$DesiredData){
 
   $nsmgr = New-Object System.XML.XmlNamespaceManager($XMLString.NameTable)    
   $nsmgr.AddNamespace('d','http://schemas.microsoft.com/ado/2007/08/dataservices')
   $nsmgr.AddNamespace('m','http://schemas.microsoft.com/ado/2007/08/dataservices/metadata')
 
 
   # Create an Array of Properties based on the 'Name' value
 
    $inputs = $XMLString.SelectNodes('//d:Name',$nsmgr)
 
   foreach ($parameter in $inputs){
      # Each 'Name' has related elements at the same level in XML
      # So the parent node is found and a new array of siblings 
      # is created.
 
      #Reset Property values 
      $obName          =""
      $obId            =""
      $obType          =""
      $obDirection     =""
      $obDescription   =""
 
      $siblings = $($parameter.ParentNode.ChildNodes)
 
      # Each of the sibling properties is identified
      foreach ($elements in $siblings){
      # write-host "Element = " $elements.ToString()
          If ($elements.ToString() -eq "Name"){
            $obName = $elements.InnerText
          }   
          If ($elements.ToString() -eq "Id"){
             $obId = $elements.InnerText
          }
          If ($elements.ToString() -eq "type"){
             $obType = $elements.InnerText
          }
          If ($elements.ToString() -eq "Direction"){
             $obDirection = $elements.InnerText
          }
         If ($elements.ToString() -eq "Description"){
            $obDescription = $elements.InnerText
         }
         If ($elements.ToString() -eq "Value"){
           # write-host "Value = "$elements.InnerText
            $obValue = $elements.InnerText
         }
       }
 
        if (($Name -eq $obName) -and ($Direction -eq $obDirection)){
          # "Correct input found"
          #Return the Requested Property
 
         If ($DesiredData -eq "Id"){
            return $obId 
         }
         If ($DesiredData -eq "Value"){
            return $obValue
         }
          }
   }
   return $Null
}

#First Part of the Body
$POSTBody = @"
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<entry xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns="http://www.w3.org/2005/Atom">
<content type="application/xml">
<m:properties>
<d:RunbookId type="Edm.Guid">{$($RunbookID)}</d:RunbookId>
<d:Parameters>&lt;Data&gt;
"@

#Now Add the Input Parameters
foreach ($p in $rbParameters.GetEnumerator())
{
    $guid=$p.Name
    $value=$p.Value
    $POSTBody+="&lt;Parameter&gt;&lt;ID&gt;{$($Guid)}&lt;/ID&gt;&lt;Value&gt;$Value&lt;/Value&gt;&lt;/Parameter&gt;"
    }

 
#The Footer of the Body
$POSTBody+=@'
&lt;/Data&gt;
</d:Parameters>
</m:properties>
</content>
</entry>
'@

#Define the Web URI and Invoje RestMethod
$OrchURI = "http://$($SCOServer):81/Orchestrator2012/Orchestrator.svc/Jobs"
$ResponseObject = Invoke-RestMethod -Uri "$($OrchURI)" -method POST -UseDefaultCredentials -Body $POSTBody -ContentType "application/atom+xml"




#Wait for the Jpb to finish
if ($WaitToCompleteRunbook)
    {
    $RunbookJobURL=$ResponseObject.entry.id
    $status = $ResponseObject.entry.content.properties.Status
    #DoExit Wil be yes, when Staet is not Pending or Running
    do
        {
	    if($status -eq "Pending" -or $status -eq "Running" )
	        { 
            $DoExit="No"
		    start-sleep -second $CheckIntervallInSeconds
            if ($IncludePendingTimeToExecutionTime -or $status -eq "Running")
                {
		        $SleepCounter = $SleepCounter + $CheckIntervallInSeconds
			    if($SleepCounter -eq $MaxExecutionTimeInSeconds)
			        {
				    $DoExit="Yes"
                    }
			    }
	        }
	    if($status -eq "Warning" -or $status -eq "Error" -or $status -eq "Completed")
    	    { 
            $DoExit="Yes"
	        }
        #Query the web service for the current status

            $ResponseObject = Invoke-RestMethod -Uri "$($RunbookJobURL)" -method Get -UseDefaultCredentials
            
        $RunbookJobURL=$ResponseObject.entry.id
        $status = $ResponseObject.entry.content.properties.Status
        }
    While($DoExit -ne "Yes")
    }

$Status


# As the runbook is no longer active, query the Instance of the submitted job
$ResponseObject = invoke-webrequest -Uri "$($RunbookJobURL)/Instances" -method Get -UseDefaultCredentials
 
#Retrieve the Instance ID
$XML                = [xml] $ResponseObject
$RunbookInstanceURL = $XML.feed.entry.id
write-host "Runbook Instance URI " $RunbookInstanceURL
 
#The Instance can be used to retrieve the Parameters for the particular job
$ResponseObject                 = invoke-webrequest -Uri "$($RunbookInstanceURL)/Parameters" -method Get -UseDefaultCredentials 
[System.Xml.XmlDocument] $xml   = $ResponseObject.Content

#Make sure to mach the Return Name in your Runbook as second Parameter
# in our Example the Name is "Return"
$RunbookResult                   = GetScorchProperty $xml "Return" "Out" "Value"

write-host "Runbook Result " $RunbookResult


