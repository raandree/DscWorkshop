function Copy-Object {
    param (
        [object]
        $DeepCopyObject
    )

    $serialData = [System.Management.Automation.PSSerializer]::Serialize($DeepCopyObject)
    [System.Management.Automation.PSSerializer]::Deserialize($serialData)
}

function Get-RelativeFileName
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    if (-not $Path)
    {
        return [string]::Empty
    }
    
    try {
        $p = Resolve-Path -Path $Path -Relative -ErrorAction Stop
        $p = $p -split '\\'
        $p[-1] = [System.IO.Path]::GetFileNameWithoutExtension($p[-1])
        $p[2..($p.Length - 1)] -join '\'
    }
    catch { }
}

function Get-RsopValueString {
    param(
        [object]$InputString,

        [string]$Key,

        [int]$Depth,

        [switch]$IsArrayValue
    )
    $fileInfo = (Get-RelativeFileName -Path $InputString.__File)

    $i = 120
    $i = if ($IsArrayValue) { 
        $Depth--
        $i - ("$InputString".Length)
    }
    else {
        $i - ($Key.Length + "$InputString".Length)
    }

    $i -= [System.Math]::Max(0, ($depth) * 2)
    "{0}$(if ($fileInfo) { ""{1,$i}""  })" -f $InputString, $fileInfo
}
function Expand-RsopHashtable
{
    param(
        [object]$InputObject,

        [switch]$IsArrayValue,

        [int]$Depth
    )

    $Depth++

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $newObject = @{}
        $keys = [string[]]$InputObject.Keys
        foreach ($key in $keys) {
            $newObject.$key = Expand-RsopHashtable -InputObject $InputObject[$key] -Depth $Depth
        }

        [ordered]@{}+$newObject
    }
    elseif ($InputObject -is [System.Collections.IList]) {
        $doesUseYamlArraySyntax = [bool]($InputObject.Count - 1)
        if (-not $doesUseYamlArraySyntax) {
            $depth--
        }
        $items = foreach ($item in $InputObject) {
            Expand-RsopHashtable -InputObject $item -IsArrayValue:$doesUseYamlArraySyntax -Depth $Depth
        }
        $items
    }
    elseif ($InputObject -is [pscredential]) {
        $cred = $InputObject.GetNetworkCredential()
        $cred = "$($cred.UserName)@$($cred.Domain)$(if($cred.Domain){':'})$($cred.Password)" | Add-Member -Name __File -MemberType NoteProperty -Value $InputObject.__File -PassThru

        Get-RsopValueString -InputString $cred -Key $key -Depth $depth -IsArrayValue:$IsArrayValue
    }
    else {
        Get-RsopValueString -InputString $InputObject -Key $key -Depth $depth -IsArrayValue:$IsArrayValue
    }
}

#Region './Classes/1.DatumProvider.ps1' 0
class DatumProvider {
    hidden [bool]$IsDatumProvider = $true

    [hashtable]ToHashTable()
    {
        $result = ConvertTo-Datum -InputObject $this
        return $result
    }

    [System.Collections.Specialized.OrderedDictionary]ToOrderedHashTable()
    {
        $result = ConvertTo-Datum -InputObject $this
        return $result
    }
}
#EndRegion './Classes/1.DatumProvider.ps1' 16
#Region './Classes/FileProvider.ps1' 0
Class FileProvider : DatumProvider {
    hidden $Path
    hidden [hashtable] $Store
    hidden [hashtable] $DatumHierarchyDefinition
    hidden [hashtable] $StoreOptions
    hidden [hashtable] $DatumHandlers
    hidden [string] $Encoding

    FileProvider ($Path, $Store, $DatumHierarchyDefinition, $Encoding)
    {
        $this.Store = $Store
        $this.DatumHierarchyDefinition = $DatumHierarchyDefinition
        $this.StoreOptions = $Store.StoreOptions
        $this.Path = Get-Item $Path -ErrorAction SilentlyContinue
        $this.DatumHandlers = $DatumHierarchyDefinition.DatumHandlers
        $this.Encoding = $Encoding

        $Result = Get-ChildItem $path | ForEach-Object {
            if($_.PSisContainer) {
                $val = [scriptblock]::Create("New-DatumFileProvider -Path `"$($_.FullName)`" -StoreOptions `$this.DataOptions -DatumHierarchyDefinition `$this.DatumHierarchyDefinition -Encoding `$this.Encoding")
                $this | Add-Member -MemberType ScriptProperty -Name $_.BaseName -Value $val
            }
            else {
                $val = [scriptblock]::Create("Get-FileProviderData -Path `"$($_.FullName)`" -DatumHandlers `$this.DatumHandlers -Encoding `$this.Encoding")
                $this | Add-Member -MemberType ScriptProperty -Name $_.BaseName -Value $val
            }
        }
    }
}
#EndRegion './Classes/FileProvider.ps1' 30
#Region './Classes/Node.ps1' 0
Class Node : hashtable {
    Node([hashtable]$NodeData)
    {
        $NodeData.keys | % {
            $This[$_] = $NodeData[$_]
        }
        
        $this | Add-member -MemberType ScriptProperty -Name Roles -Value {
            $PathArray = $ExecutionContext.InvokeCommand.InvokeScript('Get-PSCallStack')[2].Position.text -split '\.'
            $PropertyPath =  $PathArray[2..($PathArray.count-1)] -join '\'
            Write-warning "Resolve $PropertyPath"
            
            $obj = [PSCustomObject]@{}
            $currentNode = $obj
            if($PathArray.Count -gt 3) {
                foreach ($property in $PathArray[2..($PathArray.count-2)]) {
                    Write-Debug "Adding $Property property"
                    $currentNode | Add-member -MemberType NoteProperty -Name $property -Value ([PSCustomObject]@{})
                    $currentNode = $currentNode.$property
                }    
            }
            Write-Debug "Adding Resolved property to last object's property $($PathArray[-1])"
            $currentNode | Add-member -MemberType NoteProperty -Name $PathArray[-1] -Value ($PropertyPath)

            return $obj
        }
    }
    static ResolveDscProperty($Path)
    {
        "Resolve-DscProperty $Path"
    }
}
 
#EndRegion './Classes/Node.ps1' 34
#Region './Private/Compare-Hashtable.ps1' 0
function Compare-Hashtable {
    [CmdletBinding()]
    Param(
        
        $ReferenceHashtable,

        $DifferenceHashtable,

        [string[]]
        $Property = ($ReferenceHashtable.Keys + $DifferenceHashtable.Keys | Select-Object -Unique)
    )

    Write-Debug "Compare-Hashtable -Ref @{$($ReferenceHashtable.keys -join ';')} -Diff @{$($DifferenceHashtable.keys -join ';')} -Property [$($Property -join ', ')]"
    #Write-Debug "REF:`r`n$($ReferenceHashtable|ConvertTo-JSON)"
    #Write-Debug "DIFF:`r`n$($DifferenceHashtable|ConvertTo-JSON)"

    foreach ($PropertyName in $Property) {
        Write-debug "  Testing <$PropertyName>'s value"
        if( ($inRef = $ReferenceHashtable.Contains($PropertyName)) -and
            ($inDiff = $DifferenceHashtable.Contains($PropertyName))
          ) 
        {
            if($ReferenceHashtable[$PropertyName] -as [hashtable[]] -or $DifferenceHashtable[$PropertyName] -as [hashtable[]] ) {
                if( (Compare-Hashtable -ReferenceHashtable $ReferenceHashtable[$PropertyName] -DifferenceHashtable $DifferenceHashtable[$PropertyName]) ) {
                    Write-Debug "  Skipping $PropertyName...."
                    # If Compae returns something, they're not the same
                    Continue
                }
            }
            else {
                Write-Debug "Comparing: $($ReferenceHashtable[$PropertyName]) With $($DifferenceHashtable[$PropertyName])"
                if($ReferenceHashtable[$PropertyName] -ne $DifferenceHashtable[$PropertyName]) {
                    [PSCustomObject]@{
                        SideIndicator = '<='
                        PropertyName = $PropertyName
                        Value = $ReferenceHashtable[$PropertyName]
                    }

                    [PSCustomObject]@{
                        SideIndicator = '=>'
                        PropertyName = $PropertyName
                        Value = $DifferenceHashtable[$PropertyName]
                    }
                }
            }
        }
        else {
            Write-Debug "  Property $PropertyName Not in one Side: Ref: [$($ReferenceHashtable.Keys -join ',')] | [$($DifferenceHashtable.Keys -join ',')]"
            if($inRef) {
                Write-Debug "$PropertyName found in Reference hashtable"
                [PSCustomObject]@{
                    SideIndicator = '<='
                    PropertyName = $PropertyName
                    Value = $ReferenceHashtable[$PropertyName]
                }
            }
            else {
                Write-Debug "$PropertyName found in Difference hashtable"
                [PSCustomObject]@{
                    SideIndicator = '=>'
                    PropertyName = $PropertyName
                    Value = $DifferenceHashtable[$PropertyName]
                }
            }
        }
    }
    
}
#EndRegion './Private/Compare-Hashtable.ps1' 69
#Region './Private/ConvertTo-Datum.ps1' 0
function ConvertTo-Datum
{
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject,

        [AllowNull()]
        $DatumHandlers = @{}
    )

    begin {
        $HandlerNames = $DatumHandlers.Keys
    }

    process
    {
        $result = $null
        if (-not $File -and $InputObject.__File) {
            $File = $InputObject.__File
        }

        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $hashKeys = [string[]]$InputObject.Keys
            foreach ($Key in $hashKeys) {
                $InputObject[$Key] = ConvertTo-Datum -InputObject $InputObject[$Key] -DatumHandlers $DatumHandlers
            }
            
            # Making the Ordered Dict Case Insensitive
            [ordered]@{}+$InputObject
        }
        elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) {
                    ConvertTo-Datum -InputObject $object -DatumHandlers $DatumHandlers
                }
            )

            ,$collection
        }
        elseif (($InputObject -is [DatumProvider]) -and $InputObject -isnot [pscredential])
        {
            $hash = [ordered]@{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = ConvertTo-Datum -InputObject $property.Value -DatumHandlers $DatumHandlers
            }

            $hash
        }
        # if There's a matching filter, process associated command and return result
        elseif($HandlerNames.Count -and (Invoke-DatumHandler -InputObject $InputObject -DatumHandlers $DatumHandlers -HandlerNames $HandlerNames -Result ([ref]$result))) {
            if (-not $result.__File -and $InputObject.__File) {
                $result | Add-Member -Name __File -Value "$($InputObject.__File)" -MemberType NoteProperty -PassThru
            }
            elseif (-not $result.__File -and $File) {
                $result | Add-Member -Name __File -Value "$($File)" -MemberType NoteProperty -PassThru
            }
            else {
                $result
            }
        }
        else
        {
            if ($File -and -not $InputObject.__File) {
                $InputObject | Add-Member -Name __File -Value "$File" -MemberType NoteProperty -PassThru
            }
            else {
                $InputObject
            }
        }
    }
}

function Invoke-DatumHandler {
    param(
        $InputObject,

        [AllowNull()]
        $DatumHandlers,

        $HandlerNames,

        [ref]$Result
    )
    $return = $false

    foreach ($handler in $HandlerNames) {
        if ($DatumHandlers.$handler.SkipDuringLoad -and (Get-PSCallStack).Command -contains 'Get-FileProviderData') {
            continue
        }

        $FilterModule,$FilterName = $Handler -split '::'
        if(-not (Get-Module $FilterModule)) {
            Import-Module $FilterModule -force -ErrorAction Stop
        }
        $filterCommand = Get-Command -ErrorAction SilentlyContinue ("{0}\Test-{1}Filter" -f $FilterModule, $FilterName)
        if($filterCommand -and ($InputObject | &$filterCommand)) {
            try {
                if($actionCommand = Get-Command -ErrorAction SilentlyContinue ("{0}\Invoke-{1}Action" -f $FilterModule, $FilterName)) {
                    $actionParams = @{}
                    $commandOptions = $DatumHandlers.$handler.CommandOptions.Keys

                    # Populate the Command's params with what's in the Datum.yml, or from variables
                    $variables = Get-Variable
                    foreach ($paramName in $actionCommand.Parameters.Keys) {
                        if ($paramName -in $commandOptions) {
                            $actionParams.Add($paramName,$DatumHandlers.$handler.CommandOptions[$paramName])
                        }
                        elseif($var = $Variables.Where{ $_.Name -eq $paramName }) {
                            $actionParams."$paramName" = $var.Value
                        }
                    }
                    $result.Value = (&$actionCommand @actionParams)
                    if ($null -eq $result.Value) {
                        $result.Value = [string]::Empty
                    }
                    return $true
                }
            }
            catch {
                Write-Warning "Error using Datum Handler $Handler, the error was: '$($_.Exception.Message)'. Returning InputObject ($InputObject)."
                $result = $InputObject
                return $false
            }
        }
    }

    return $return
}
#EndRegion './Private/ConvertTo-Datum.ps1' 88
#Region './Private/Get-DatumType.ps1' 0
function Get-DatumType {
    param (
        [object]
        $DatumObject
    )

    if ($DatumObject -is [hashtable] -or $DatumObject -is [System.Collections.Specialized.OrderedDictionary]) {
        "hashtable"
    }
    elseif($DatumObject -isnot [string] -and $DatumObject -is [System.Collections.IEnumerable]) {
        if($Datumobject -as [hashtable[]]) {
            "hash_array"
        }
        else {
            "baseType_array"
        }
        
    }
    else {
        "baseType"
    }

}
#EndRegion './Private/Get-DatumType.ps1' 24
#Region './Private/Get-MergeStrategyFromString.ps1' 0
<#
MergeStrategy: MostSpecific
        merge_hash: MostSpecific
        merge_baseType_array: MostSpecific
        merge_hash_array: MostSpecific

MergeStrategy: hash
        merge_hash: hash
        merge_baseType_array: MostSpecific
        merge_hash_array: MostSpecific
        merge_options:
        knockout_prefix: --

MergeStrategy: Deep
        merge_hash: deep
        merge_baseType_array: Unique
        merge_hash_array: DeepTuple
        merge_options:
        knockout_prefix: --
        Tuple_Keys:
            - Name
            - Version
#>
function Get-MergeStrategyFromString {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [String]
        $MergeStrategy
    )
    
    Write-Debug "Get-MergeStrategyFromString -MergeStrategy <$MergeStrategy>"
    switch -regex ($MergeStrategy) {
        '^First$|^MostSpecific$' { 
            @{
                merge_hash = 'MostSpecific'
                merge_baseType_array = 'MostSpecific'
                merge_hash_array = 'MostSpecific'
            }
        }

        '^hash$|^MergeTopKeys$' {
            @{
                merge_hash = 'hash'
                merge_baseType_array = 'MostSpecific'
                merge_hash_array = 'MostSpecific'
                merge_options = @{
                    knockout_prefix = '--'
                }
            }
        }

        '^deep$|^MergeRecursively$' {
            @{
                merge_hash = 'deep'
                merge_baseType_array = 'Unique'
                merge_hash_array = 'DeepTuple'
                merge_options = @{
                    knockout_prefix = '--'
                    tuple_keys = @(
                        'Name'
                        ,'Version'
                    )
                }
            }
        }
        default {
            Write-Debug "Couldn't Match the strategy $MergeStrategy"
            @{
                merge_hash = 'MostSpecific'
                merge_baseType_array = 'MostSpecific'
                merge_hash_array = 'MostSpecific'
            }
        }
    }
    
}
#EndRegion './Private/Get-MergeStrategyFromString.ps1' 78
#Region './Private/Merge-DatumArray.ps1' 0
function Merge-DatumArray {
    [CmdletBinding()]
    Param(
        $ReferenceArray,

        $DifferenceArray,

        $Strategy = @{ },

        $ChildStrategies = @{'^.*' = $Strategy},

        $StartingPath
    )

    Write-Debug "`tMerge-DatumArray -StartingPath <$StartingPath>"
    $knockout_prefix = [regex]::Escape($Strategy.merge_options.knockout_prefix).insert(0,'^')
    $HashArrayStrategy = $Strategy.merge_hash_array
    Write-Debug "`t`tHash Array Strategy: $HashArrayStrategy"
    $MergeBasetypeArraysStrategy = $Strategy.merge_basetype_array
    $MergedArray = [System.Collections.ArrayList]::new()

    $SortParams = @{}
    if($PropertyNames = [String[]]$Strategy.merge_options.tuple_keys) {
        $SortParams.Add('Property',$PropertyNames)
    }

    if($ReferenceArray -as [hashtable[]]) {
        Write-Debug "`t`tMERGING Array of Hashtables"
        if(!$HashArrayStrategy -or $HashArrayStrategy -match 'MostSpecific') {
            Write-Debug "`t`tMerge_hash_arrays Disabled. value: $HashArrayStrategy"
            $MergedArray = $ReferenceArray
            if($Strategy.sort_merged_arrays) {
                $MergedArray = $MergedArray | Sort-Object @SortParams
            }
            return $MergedArray
        }

        switch -Regex ($HashArrayStrategy) {
            '^Sum|^Add' {
                (@($DifferenceArray) + @($ReferenceArray)) | Foreach-Object {
                    $null = $MergedArray.add(([ordered]@{}+$_))
                }
            }

            # MergeHashesByProperties
            '^Deep|^Merge' {
                Write-Debug "`t`t`tStrategy for Array Items: Merge Hash By tuple`r`n"
                # look at each $RefItems in $RefArray
                #   if no PropertyNames defined, use all Properties of $RefItem
                #   else use defined propertyNames
                #  Search for DiffItem that has the same Property/Value pairs
                #    if found, Merge-Datum (or MergeHashtable?)
                #    if not found, add $DiffItem to $RefArray

                # look at each $RefItems in $RefArray
                $UsedDiffItems = [System.Collections.ArrayList]::new()
                foreach ($ReferenceItem in $ReferenceArray) {
                    $ReferenceItem = [ordered]@{} + $ReferenceItem
                    Write-Debug "`t`t`t  .. Working on Merged Element $($MergedArray.Count)`r`n"
                    # if no PropertyNames defined, use all Properties of $RefItem
                    if(!$PropertyNames) {
                        Write-Debug "`t`t`t ..No PropertyName defined: Use ReferenceItem Keys"
                        $PropertyNames = $ReferenceItem.Keys
                    }
                    $MergedItem = @{} + $ReferenceItem
                    $DiffItemsToMerge = $DifferenceArray.Where{
                        $DifferenceItem = [ordered]@{} + $_
                        # Search for DiffItem that has the same Property/Value pairs than RefItem
                        $CompareHashParams = @{
                            ReferenceHashtable = [ordered]@{}+$ReferenceItem
                            DifferenceHashtable = $DifferenceItem
                            Property = $PropertyNames
                        }
                        (!(Compare-Hashtable @CompareHashParams))
                    }
                    Write-Debug "`t`t`t ..Items to merge: $($DiffItemsToMerge.Count)"
                    $DiffItemsToMerge | Foreach-Object {
                        $MergeItemsParams = @{
                            ParentPath = $StartingPath
                            Strategy = $Strategy
                            ReferenceHashtable = $MergedItem
                            DifferenceHashtable = $_
                            ChildStrategies = $ChildStrategies
                        }
                        $MergedItem = Merge-Hashtable @MergeItemsParams
                    }
                    # If a diff Item has been used, save it to find the unused ones
                    $null = $UsedDiffItems.AddRange($DiffItemsToMerge)
                    $null = $MergedArray.Add($MergedItem)
                }
                $UnMergedItems = $DifferenceArray | Foreach-Object {
                    if(!$UsedDiffItems.Contains($_)) {
                        ([ordered]@{} + $_)
                    }
                }
                if ($null -ne $UnMergedItems)
                {
                    if ($UnMergedItems -is [System.Array])
                    {
                        $null = $MergedArray.AddRange($UnMergedItems)
                    }
                    else
                    {
                        $null = $MergedArray.Add($UnMergedItems)
                    }
                }
            }

            # UniqueByProperties
            '^Unique' {
                Write-Debug "`t`t`tSelecting Unique Hashes accross both arrays based on Property tuples"
                # look at each $DiffItems in $DiffArray
                #   if no PropertyNames defined, use all Properties of $DiffItem
                #   else use defined PropertyNames
                #  Search for a RefItem that has the same Property/Value pairs
                #  if Nothing is found
                #    add current DiffItem to RefArray

                if(!$PropertyNames) {
                    Write-Debug "`t`t`t ..No PropertyName defined: Use ReferenceItem Keys"
                    $PropertyNames = $ReferenceItem.Keys
                }

                $MergedArray = [System.Collections.ArrayList]::new()
                $ReferenceArray | Foreach-Object {
                    $CurrentRefItem = $_
                    if(!( $MergedArray.Where{!(Compare-Hashtable -Property $PropertyNames -ReferenceHashtable $CurrentRefItem -DifferenceHashtable $_ )})) {
                        $null = $MergedArray.Add(([ordered]@{} +$_))
                    }
                }

                $DifferenceArray | Foreach-Object {
                    $CurrentDiffItem = $_
                    if(!( $MergedArray.Where{!(Compare-Hashtable -Property $PropertyNames -ReferenceHashtable $CurrentDiffItem -DifferenceHashtable $_ )})) {
                        $null = $MergedArray.Add(([ordered]@{} +$_))
                    }
                }
            }
        }
    }

    $MergedArray
}
#EndRegion './Private/Merge-DatumArray.ps1' 144
#Region './Private/Merge-Hashtable.ps1' 0
function Merge-Hashtable {
    [outputType([hashtable])]
    [cmdletBinding()]
    Param(
        # [hashtable] These should stay ordered
        $ReferenceHashtable,

        # [hashtable] These should stay ordered
        $DifferenceHashtable,

        $Strategy = @{
            merge_hash = 'hash'
            merge_baseType_array = 'MostSpecific'
            merge_hash_array = 'MostSpecific'
            merge_options = @{
                knockout_prefix = '--'
            }
        },

        $ChildStrategies = @{},

        [string]
        $ParentPath
    )

    Write-Debug "`tMerge-Hashtable -ParentPath <$ParentPath>"
    # Removing Case Sensitivity while keeping ordering
    $ReferenceHashtable  = [ordered]@{} + $ReferenceHashtable
    $DifferenceHashtable = [ordered]@{} + $DifferenceHashtable
    $clonedReference     = [ordered]@{} + $ReferenceHashtable

    if ($Strategy.merge_options.knockout_prefix) {
        $KnockoutPrefix = $Strategy.merge_options.knockout_prefix
        $KnockoutPrefixMatcher = [regex]::escape($KnockoutPrefix).insert(0,'^')
    }
    else {
        $KnockoutPrefixMatcher = [regex]::escape('--').insert(0,'^')
    }
    Write-Debug "`t  Knockout Prefix Matcher: $knockoutPrefixMatcher"

    $knockedOutKeys = $ReferenceHashtable.keys.where{$_ -match $KnockoutPrefixMatcher}.foreach{$_ -replace $KnockoutPrefixMatcher}
    Write-Debug "`t  Knockedout Keys: [$($knockedOutKeys -join ', ')] from reference Hashtable Keys [$($ReferenceHashtable.keys -join ', ')]"

    foreach ($currentKey in $DifferenceHashtable.keys) {
        Write-Debug "`t  CurrentKey: $currentKey"
        if($currentKey -in $knockedOutKeys) {
            Write-Debug "`t`tThe Key $currentkey is knocked out from the reference Hashtable."
        }
        elseif ($currentKey -match $KnockoutPrefixMatcher -and !$ReferenceHashtable.contains(($currentKey -replace $KnockoutPrefixMatcher))) {
            # it's a knockout coming from a lower level key, it should only apply down from here
            Write-Debug "`t`tKnockout prefix found for $currentKey in Difference hashtable, and key not set in Reference hashtable"
            if(!$ReferenceHashtable.contains($currentKey)) {
                Write-Debug "`t`t..adding knockout prefixed key for $curretKey to block further merges"
                $clonedReference.add($currentKey,$null)
            }
        }
        elseif (!$ReferenceHashtable.contains($currentKey) )  {
            #if the key does not exist in reference ht, create it using the DiffHt's value
            Write-Debug "`t    Added Missing Key $currentKey of value: $($DifferenceHashtable[$currentKey]) from difference HT"
            if (-not ($clonedReference.Keys -contains $currentKey)) {
                $clonedReference."$currentKey" = $DifferenceHashtable[$currentKey]
            }
        }
        else { #the key exists, and it's not a knockout entry
            $RefHashItemValueType  = Get-DatumType $ReferenceHashtable[$currentKey]
            $DiffHashItemValueType = Get-DatumType $DifferenceHashtable[$currentKey]
            Write-Debug "for Key $currentKey REF:[$RefHashItemValueType] | DIFF:[$DiffHashItemValueType]"
            if($ParentPath) {
                $ChildPath = (Join-Path  $ParentPath $currentKey)
            }
            else {
                $ChildPath = $currentKey
            }

            switch ($RefHashItemValueType) {
                'hashtable'      {
                    if($Strategy.merge_hash -eq 'deep') {
                        Write-Debug "`t`t .. Merging Datums at current path $ChildPath"
                        # if there's no Merge override for the subkey's path in the (not subkeys),
                        #   merge HASHTABLE with same strategy
                        # otherwise, merge Datum
                        $ChildStrategy = Get-MergeStrategyFromPath -Strategies $ChildStrategies -PropertyPath $ChildPath

                        if($ChildStrategy.Default) {
                            Write-Debug "`t`t ..Merging using the current Deep Strategy, Bypassing default"
                            $MergePerDefault = @{
                                ParentPath = $ChildPath
                                Strategy = $Strategy
                                ReferenceHashtable = $ReferenceHashtable[$currentKey]
                                DifferenceHashtable = $DifferenceHashtable[$currentKey]
                                ChildStrategies = $ChildStrategies
                            }
                            $subMerge = Merge-Hashtable @MergePerDefault
                        }
                        else {
                            Write-Debug "`t`t ..Merging using Override Strategy $($ChildStrategy|ConvertTo-Json)"
                            $MergeDatumParam = @{
                                StartingPath = $ChildPath
                                ReferenceDatum = $ReferenceHashtable[$currentKey]
                                DifferenceDatum = $DifferenceHashtable[$currentKey]
                                Strategies = $ChildStrategies
                            }
                            $subMerge = Merge-Datum @MergeDatumParam
                        }
                        Write-Debug "`t  # Submerge $($submerge|ConvertTo-Json)."
                        $clonedReference[$currentKey]  = $subMerge
                    }
                }

                'baseType'       {
                    #do nothing to use most specific value (quicker than default)
                }

                # Default used for hash_array, baseType_array
                Default {
                    Write-Debug "`t  .. Merging Datums at current path $ChildPath`r`n$($Strategy|ConvertTo-Json)"
                    $MergeDatumParams = @{
                        StartingPath = $ChildPath
                        Strategies = $ChildStrategies
                        ReferenceDatum = $ReferenceHashtable[$currentKey]
                        DifferenceDatum = $DifferenceHashtable[$currentKey]
                    }

                    #$clonedReference[$currentKey]  = Merge-Datum @MergeDatumParams
                    if ($clonedReference.$currentKey -is [System.Array])
                    {
                        [System.Array]$clonedReference[$currentKey] = Merge-Datum @MergeDatumParams
                    }
                    else
                    {
                        $clonedReference[$currentKey] = Merge-Datum @MergeDatumParams
                    }
                    Write-Debug "`t  .. Datum Merged for path $ChildPath"
                }
            }
        }
    }

    return $clonedReference
}
#EndRegion './Private/Merge-Hashtable.ps1' 131
#Region './Public/Get-DatumRSOP.ps1' 0
function Get-DatumRsop {
    [CmdletBinding()]
    param (
        $Datum,

        [hashtable[]]
        $AllNodes,

        [string]
        $CompositionKey = 'Configurations',

        [ScriptBlock]
        $Filter = {},

        [switch]
        $IgnoreCache,

        [switch]
        $IncludeSource
    )

    if (-not $script:rsopCache) {
        $script:rsopCache = @{}
    }

    if ($Filter.ToString() -ne ([System.Management.Automation.ScriptBlock]::Create({})).ToString()) {
        Write-Verbose "Filter: $($Filter.ToString())"
        $AllNodes = [System.Collections.Hashtable[]]$allNodes.Where($Filter)
        Write-Verbose "Node count after applying filter: $($AllNodes.Count)"
    }

    foreach ($Node in $AllNodes) {
        if (-not $Node.Name) {
            $Node.Name = $Node.NodeName
        }

        $null = $node | ConvertTo-Datum -DatumHandlers $Datum.__Definition.DatumHandlers

        if (-not $script:rsopCache.ContainsKey($Node.Name) -or $IgnoreCache) {
            Write-Verbose "Key not found in the cache: '$($Node.Name)'. Creating RSOP..."
            $rsopNode = $Node.Clone()

            $Configurations = Lookup $CompositionKey -Node $Node -DatumTree $Datum -DefaultValue @()
            $rsopNode."$CompositionKey" = $Configurations

            $Configurations.ForEach{
                $value = Lookup $_ -DefaultValue @{} -Node $Node -DatumTree $Datum
                $rsopNode."$_" = $value
            }

            $lcmConfig = Resolve-NodeProperty -PropertyPath LcmConfig -DefaultValue $null
            if ($lcmConfig) {
                $rsopNode.LcmConfig = $lcmConfig
            }

            $clonedRsopNode = Copy-Object -DeepCopyObject $rsopNode
            $clonedRsopNode = ConvertTo-Datum -InputObject $clonedRsopNode -DatumHandlers $Datum.__Definition.DatumHandlers
            $script:rsopCache."$($Node.Name)" = $clonedRsopNode
        }
        else {
            Write-Verbose "Key found in the cache: '$($Node.Name)'. Retrieving RSOP from cache."
        }

        if ($IncludeSource) {
            Expand-RsopHashtable -InputObject $script:rsopCache."$($Node.Name)" -Depth 0
        }
        else {
            $script:rsopCache."$($Node.Name)"
        }
    }
}

#EndRegion './Public/Get-DatumRSOP.ps1' 36
#Region './Public/Get-FileProviderData.ps1' 0
function Get-FileProviderData {
    [CmdletBinding()]
    Param(
        $Path,

        [AllowNull()]
        $DatumHandlers = @{},

        [ValidateSet('Ascii', 'BigEndianUnicode', 'Default', 'Unicode', 'UTF32', 'UTF7', 'UTF8')]
        [string]
        $Encoding = 'Default'
    )

    begin {
        if(!$script:FileProviderDataCache) {
            $script:FileProviderDataCache = @{}
        }
    }

    process {
        $File = Get-Item -Path $Path
        if($script:FileProviderDataCache.ContainsKey($File.FullName) -and
        $File.LastWriteTime -eq $script:FileProviderDataCache[$File.FullName].Metadata.LastWriteTime) {
            Write-Verbose "Getting File Provider Cache for Path: $Path"
            ,$script:FileProviderDataCache[$File.FullName].Value
        } else {
            Write-Verbose "Getting File Provider Data for Path: $Path"
            $data = switch ($File.Extension) {
                '.psd1' {
                    Import-PowerShellDataFile -Path $File | ConvertTo-Datum -DatumHandlers $DatumHandlers
                }
                '.json' {
                    ConvertFrom-Json (Get-Content -Path $Path -Encoding $Encoding -Raw) | ConvertTo-Datum -DatumHandlers $DatumHandlers
                }
                '.yml' {
                    ConvertFrom-Yaml (Get-Content -Path $Path -Encoding $Encoding -Raw) -Ordered | ConvertTo-Datum -DatumHandlers $DatumHandlers
                }
                '.yaml' {
                    ConvertFrom-Yaml (Get-Content -Path $Path -Encoding $Encoding -Raw) -Ordered | ConvertTo-Datum -DatumHandlers $DatumHandlers
                }
                Default {
                    Write-verbose "File extension $($File.Extension) not supported. Defaulting on RAW."
                    Get-Content -Path $Path -Encoding $Encoding -Raw
                }
            }

            $script:FileProviderDataCache[$File.FullName] = @{
                Metadata = $File
                Value = $data
            }
            ,$data
        }
    }
}
#EndRegion './Public/Get-FileProviderData.ps1' 55
#Region './Public/Get-MergeStrategyFromPath.ps1' 0
function Get-MergeStrategyFromPath {
    [CmdletBinding()]
    Param(
        $Strategies,

        $PropertyPath
    )
    Write-debug "`tGet-MergeStrategyFromPath -PropertyPath <$PropertyPath> -Strategies [$($Strategies.keys -join ', ')], count $($Strategies.count)"
    # Select Relevant strategy
    #   Use exact path match first
    #   or try Regex in order
    if ($Strategies.($PropertyPath)) {
        $StrategyKey = $PropertyPath
        Write-debug "`t  Strategy found for exact key $StrategyKey"
    }
    elseif($Strategies.keys -and
            ($StrategyKey = [string]($Strategies.keys.where{$_.StartsWith('^') -and $_ -as [regex] -and $PropertyPath -match $_} | Select-Object -First 1))
          ) 
    {
        Write-debug "`t  Strategy matching regex $StrategyKey"
    }
    else {
        Write-debug "`t  No Strategy found"
        return
    }

    Write-Debug "`t  StrategyKey: $StrategyKey"
    if( $Strategies[$StrategyKey] -is [string]) {
        Write-debug "`t  Returning Strategy $StrategyKey from String '$($Strategies[$StrategyKey])'"
        Get-MergeStrategyFromString $Strategies[$StrategyKey]
    }
    else {
        Write-Debug "`t  Returning Strategy $StrategyKey of type '$($Strategies[$StrategyKey].Strategy)'"
        $Strategies[$StrategyKey]
    }
}
#EndRegion './Public/Get-MergeStrategyFromPath.ps1' 37
#Region './Public/Invoke-TestHandlerAction.ps1' 0
function Invoke-TestHandlerAction {
    Param(
        $Password,

        $test,

        $Datum
    )
@"
    Action: $handler
    Node: $($Node|FL *|Out-String)
    Params: 
$($PSBoundParameters | Convertto-Json)
"@
}
#EndRegion './Public/Invoke-TestHandlerAction.ps1' 16
#Region './Public/Merge-Datum.ps1' 0
function Merge-Datum {
    [CmdletBinding()]
    param (
        [string]
        $StartingPath,

        $ReferenceDatum,

        $DifferenceDatum,

        $Strategies = @{
            '^.*' = 'MostSpecific'
        }
    )

    Write-Debug "Merge-Datum -StartingPath <$StartingPath>"
    $Strategy = Get-MergeStrategyFromPath -Strategies $strategies -PropertyPath $startingPath -Verbose

    Write-Verbose "   Merge Strategy: @$($Strategy | ConvertTo-Json)"

    $ReferenceDatumType  = Get-DatumType -DatumObject $ReferenceDatum
    $DifferenceDatumType = Get-DatumType -DatumObject $DifferenceDatum

    if($ReferenceDatumType -ne $DifferenceDatumType) {
        Write-Warning "Cannot merge different types in path '$StartingPath' REF:[$ReferenceDatumType] | DIFF:[$DifferenceDatumType]$($DifferenceDatum.GetType()) , returning most specific Datum."
        return $ReferenceDatum
    }

    if($Strategy -is [string]) {
        $Strategy = Get-MergeStrategyFromString -MergeStrategy $Strategy
    }

    switch ($ReferenceDatumType) {
        'BaseType' {
            return $ReferenceDatum
        }

        'hashtable' {
            $mergeParams = @{
                ReferenceHashtable  = $ReferenceDatum
                DifferenceHashtable = $DifferenceDatum
                Strategy = $Strategy
                ParentPath = $StartingPath
                ChildStrategies = $Strategies
            }

            if($Strategy.merge_hash -match '^MostSpecific$|^First') {
                return $ReferenceDatum
            }
            else {
                Merge-Hashtable @mergeParams
            }
        }

        'baseType_array' {
            switch -Regex ($Strategy.merge_baseType_array) {
                '^MostSpecific$|^First' { return $ReferenceDatum }

                '^Unique'   {
                    if($regexPattern = $Strategy.merge_options.knockout_prefix) {
                        $regexPattern = $regexPattern.insert(0,'^')
                        $result = @(($ReferenceDatum + $DifferenceDatum).Where{$_ -notmatch $regexPattern} | Select-object -Unique)
                        ,$result
                    }
                    else {
                        $result = @(($ReferenceDatum + $DifferenceDatum) | Select-Object -Unique)
                        ,$result
                    }

                }

                '^Sum|^Add' {
                    #--> $ref + $diff -$kop
                    if($regexPattern = $Strategy.merge_options.knockout_prefix) {
                        $regexPattern = $regexPattern.insert(0,'^')
                        ,(($ReferenceDatum + $DifferenceDatum).Where{$_ -notMatch $regexPattern})
                    }
                    else {
                        ,($ReferenceDatum + $DifferenceDatum)
                    }
                }

                Default { return (,$ReferenceDatum) }
            }
        }

        'hash_array' {
            $MergeDatumArrayParams = @{
                ReferenceArray = $ReferenceDatum
                DifferenceArray = $DifferenceDatum
                Strategy = $Strategy
                ChildStrategies = $Strategies
                StartingPath = $StartingPath
            }

            switch -Regex ($Strategy.merge_hash_array) {
                '^MostSpecific|^First' { return $ReferenceDatum }

                '^UniqueKeyValTuples'  {
                    #--> $ref + $diff | ? % key in Tuple_Keys -> $ref[Key] -eq $diff[key] is not already int output
                    ,(Merge-DatumArray @MergeDatumArrayParams)
                }

                '^DeepTuple|^DeepItemMergeByTuples' {
                    #--> $ref + $diff | ? % key in Tuple_Keys -> $ref[Key] -eq $diff[key] is merged up
                    ,(Merge-DatumArray @MergeDatumArrayParams)
                }

                '^Sum' {
                    #--> $ref + $diff
                    (@($DifferenceArray) + @($ReferenceArray)).Foreach{
                        $null = $MergedArray.add(([ordered]@{}+$_))
                    }
                    ,$MergedArray
                }

                Default { return (,$ReferenceDatum) }
            }
        }
    }
}
#EndRegion './Public/Merge-Datum.ps1' 122
#Region './Public/New-DatumFileProvider.ps1' 0
function New-DatumFileProvider {
    Param(

        [alias('DataOptions')]
        [AllowNull()]
        $Store,

        [AllowNull()]
        $DatumHierarchyDefinition = @{},

        $Path = $Store.StoreOptions.Path,

        [ValidateSet('Ascii', 'BigEndianUnicode', 'Default', 'Unicode', 'UTF32', 'UTF7', 'UTF8')]
        [string]
        $Encoding = 'Default'
    )

    if (!$DatumHierarchyDefinition) {
        $DatumHierarchyDefinition = @{}
    }

    [FileProvider]::new($Path, $Store, $DatumHierarchyDefinition, $Encoding)
}
#EndRegion './Public/New-DatumFileProvider.ps1' 24
#Region './Public/New-DatumStructure.ps1' 0
function New-DatumStructure {
    [CmdletBinding(
        DefaultParameterSetName = 'FromConfigFile'
    )]

    Param (
        [Parameter(
            Mandatory,
            ParameterSetName = 'DatumHierarchyDefinition'
        )]
        [Alias('Structure')]
        [hashtable]
        $DatumHierarchyDefinition,

        [Parameter(
            Mandatory,
            ParameterSetName = 'FromConfigFile'
        )]
        [io.fileInfo]
        $DefinitionFile,

        [ValidateSet('Ascii', 'BigEndianUnicode', 'Default', 'Unicode', 'UTF32', 'UTF7', 'UTF8')]
        [string]
        $Encoding = 'Default'
    )

    switch ($PSCmdlet.ParameterSetName) {
        'DatumHierarchyDefinition' {
            if ($DatumHierarchyDefinition.contains('DatumStructure')) {
                Write-debug "Loading Datum from Parameter"
            }
            elseif($DatumHierarchyDefinition.Path) {
                $DatumHierarchyFolder = $DatumHierarchyDefinition.Path
                Write-Debug "Loading default Datum from given path $DatumHierarchyFolder"
            }
            else {
                Write-Warning "Desperate attempt to load Datum from Invocation origin..."
                $CallStack = Get-PSCallstack
                $DatumHierarchyFolder = $CallStack[-1].psscritroot
                Write-Warning " ---> $DatumHierarchyFolder"
            }
        }

        'FromConfigFile' {
            if((Test-Path $DefinitionFile)) {
                $DefinitionFile = (Get-Item $DefinitionFile -ErrorAction Stop)
                Write-Debug "File $DefinitionFile found. Loading..."
                $DatumHierarchyDefinition = Get-FileProviderData $DefinitionFile.FullName -Encoding $Encoding
                if(!$DatumHierarchyDefinition.contains('ResolutionPrecedence')) {
                    Throw 'Invalid Datum Hierarchy Definition'
                }
                $DatumHierarchyFolder = $DefinitionFile.directory.FullName
                Write-Debug "Datum Hierachy Parent folder: $DatumHierarchyFolder"
            }
            else {
                Throw "Datum Hierarchy Configuration not found"
            }
        }
    }

    $root = @{}
    if($DatumHierarchyFolder -and !$DatumHierarchyDefinition.DatumStructure) {
       $Structures = foreach ($Store in (Get-ChildItem -Directory -Path $DatumHierarchyFolder)) {
           @{
               StoreName = $Store.BaseName
               StoreProvider = 'Datum::File'
               StoreOptions = @{
                   Path = $Store.FullName
               }
           }
       }

       if($DatumHierarchyDefinition.contains('DatumStructure')) {
           $DatumHierarchyDefinition['DatumStructure'] = $Structures
       }
       else {
           $DatumHierarchyDefinition.add('DatumStructure',$Structures)
       }
    }

    # Define the default hierachy to be the StoreNames, when nothing is specified
    if ($DatumHierarchyFolder -and !$DatumHierarchyDefinition.ResolutionPrecedence) {
        if($DatumHierarchyDefinition.contains('ResolutionPrecedence')) {
            $DatumHierarchyDefinition['ResolutionPrecedence'] = $Structures.StoreName
        }
        else {
            $DatumHierarchyDefinition.add('ResolutionPrecedence',$Structures.StoreName)
        }
    }
    # Adding the Datum Definition to Root object
    $root.add('__Definition',$DatumHierarchyDefinition)

    foreach ($store in $DatumHierarchyDefinition.DatumStructure){
        $StoreParams = @{
            Store    =  (ConvertTo-Datum ([hashtable]$Store).clone())
            Path     = $store.StoreOptions.Path
            Encoding = $Encoding
        }

        # Accept Module Specification for Store Provider as String (unversioned) or Hashtable
        if($Store.StoreProvider -is [string]) {
            $StoreProviderModule, $StoreProviderName = $store.StoreProvider -split '::'
        }
        else {
            $StoreProviderModule = $Store.StoreProvider.ModuleName
            $StoreProviderName = $Store.StoreProvider.ProviderName
            if($Store.StoreProvider.ModuleVersion) {
                $StoreProviderModule = @{
                    ModuleName = $StoreProviderModule
                    ModuleVersion = $Store.StoreProvider.ModuleVersion
                }
            }
        }

        if(!($Module = Get-Module $StoreProviderModule -ErrorAction SilentlyContinue)) {
            $Module = Import-Module $StoreProviderModule -Force -ErrorAction Stop -PassThru
        }
        $ModuleName = ($Module | Select-Object -First 1).Name

        $NewProvidercmd = Get-Command ("{0}\New-Datum{1}Provider" -f $ModuleName, $StoreProviderName)

        if( $StoreParams.Path -and
            ![io.path]::IsPathRooted($StoreParams.Path) -and
            $DatumHierarchyFolder
        ) {
            Write-Debug "Replacing Store Path with AbsolutePath"
            $StorePath = Join-Path $DatumHierarchyFolder $StoreParams.Path -Resolve -ErrorAction Stop
            $StoreParams['Path'] = $StorePath
        }

        if ($NewProvidercmd.Parameters.keys -contains 'DatumHierarchyDefinition') {
            Write-Debug "Adding DatumHierarchyDefinition to Store Params"
            $StoreParams.add('DatumHierarchyDefinition',$DatumHierarchyDefinition)
        }

        $storeObject = &$NewProvidercmd @StoreParams
        Write-Debug "Adding key $($store.storeName) to Datum root object"
        $root.Add($store.StoreName,$storeObject)
    }

    #return the Root Datum hashtable
    $root
}
#EndRegion './Public/New-DatumStructure.ps1' 144
#Region './Public/Resolve-Datum.ps1' 0
Function Resolve-Datum {
    [cmdletBinding()]
    Param(
        [Parameter(
            Mandatory
        )]
        [string]
        $PropertyPath,

        [Parameter(
            Position = 1
        )]
        [Alias('Node')]
        $Variable = $ExecutionContext.InvokeCommand.InvokeScript('$Node'),

        [string]
        $VariableName = 'Node',

        [Alias('DatumStructure')]
        $DatumTree = $ExecutionContext.InvokeCommand.InvokeScript('$ConfigurationData.Datum'),

        [Parameter(
            ParameterSetName = 'UseMergeOptions'
        )]
        [Alias('SearchBehavior')]
        $options,

        [string[]]
        [Alias('SearchPaths')]
        $PathPrefixes = $DatumTree.__Definition.ResolutionPrecedence,

        [int]
        $MaxDepth = $(
            if ($MxdDpth = $DatumTree.__Definition.default_lookup_options.MaxDepth) {
                $MxdDpth
            }
            else {
                -1
            })
    )

    # Manage lookup options:
    <#
    default_lookup_options	Lookup_options	options (argument)	Behaviour
                MostSpecific for ^.*
    Present			default_lookup_options + most Specific if not ^.*
        Present		lookup_options + Default to most Specific if not ^.*
            Present	options + Default to Most Specific if not ^.*
    Present	Present		Lookup_options + Default for ^.* if !Exists
    Present		Present	options + Default for ^.* if !Exists
        Present	Present	options override lookup options + Most Specific if !Exists
    Present	Present	Present	options override lookup options + default for ^.*


    +========================+================+====================+============================================================+
    | default_lookup_options | Lookup_options | options (argument) |                         Behaviour                          |
    +========================+================+====================+============================================================+
    |                        |                |                    | MostSpecific for ^.*                                       |
    +------------------------+----------------+--------------------+------------------------------------------------------------+
    | Present                |                |                    | default_lookup_options + most Specific if not ^.*          |
    +------------------------+----------------+--------------------+------------------------------------------------------------+
    |                        | Present        |                    | lookup_options + Default to most Specific if not ^.*       |
    +------------------------+----------------+--------------------+------------------------------------------------------------+
    |                        |                | Present            | options + Default to Most Specific if not ^.*              |
    +------------------------+----------------+--------------------+------------------------------------------------------------+
    | Present                | Present        |                    | Lookup_options + Default for ^.* if !Exists                |
    +------------------------+----------------+--------------------+------------------------------------------------------------+
    | Present                |                | Present            | options + Default for ^.* if !Exists                       |
    +------------------------+----------------+--------------------+------------------------------------------------------------+
    |                        | Present        | Present            | options override lookup options + Most Specific if !Exists |
    +------------------------+----------------+--------------------+------------------------------------------------------------+
    | Present                | Present        | Present            | options override lookup options + default for ^.*          |
    +------------------------+----------------+--------------------+------------------------------------------------------------+

    If there's no default options, auto-add default options of mostSpecific merge, and tag as 'default'
    if there's a default options, use that strategy and tag as 'default'
    if the options implements ^.*, do not add Default_options, and do not tag

    1. Defaults to Most Specific
    2. Allow setting your own default, with precedence for non-default options
    3. Overriding ^.* without tagging it as default (always match unless)

    #>

    Write-Debug "Resolve-Datum -PropertyPath <$PropertyPath> -Node $($Node.Name)"
    # Make options an ordered case insensitive variable
    if ($options) {
        $options = [ordered]@{} + $options
    }

    if ( !$DatumTree.__Definition.default_lookup_options ) {
        $default_options = Get-MergeStrategyFromString
        Write-Verbose "  Default option not found in Datum Tree"
    }
    else {
        if ($DatumTree.__Definition.default_lookup_options -is [string]) {
            $default_options = $(Get-MergeStrategyFromString -MergeStrategy $DatumTree.__Definition.default_lookup_options)
        }
        else {
            $default_options = $DatumTree.__Definition.default_lookup_options
        }
        #TODO: Add default_option input validation
        Write-Verbose "  Found default options in Datum Tree of type $($default_options.Strategy)."
    }

    if ( $DatumTree.__Definition.lookup_options) {
        Write-Debug "  Lookup options found."
        $lookup_options = @{} + $DatumTree.__Definition.lookup_options
    }
    else {
        $lookup_options = @{}
    }

    # Transform options from string to strategy hashtable
    foreach ($optKey in ([string[]]$lookup_options.keys)) {
        if ($lookup_options[$optKey] -is [string]) {
            $lookup_options[$optKey] = Get-MergeStrategyFromString -MergeStrategy $lookup_options[$optKey]
        }
    }

    foreach ($optKey in ([string[]]$options.keys)) {
        if ($options[$optKey] -is [string]) {
            $options[$optKey] = Get-MergeStrategyFromString -MergeStrategy $options[$optKey]
        }
    }

    # using options if specified or lookup_options otherwise
    if (!$options) {
        $options = $lookup_options
    }

    # Add default strategy for ^.* if not present, at the end
    if (([string[]]$Options.keys) -notcontains '^.*') {
        # Adding Default flag
        $default_options['Default'] = $true
        $options.add('^.*', $default_options)
    }

    # Create the variable to be used as Pivot in prefix path
    if ( $Variable -and $VariableName ) {
        Set-Variable -Name $VariableName -Value $Variable -Force
    }

    # Scriptblock in path detection patterns
    $Pattern = '(?<opening><%=)(?<sb>.*?)(?<closure>%>)'
    $PropertySeparator = [IO.Path]::DirectorySeparatorChar
    $splitPattern = [regex]::Escape($PropertySeparator)

    $Depth = 0
    $MergeResult = $null

    # Get the strategy for this path, to be used for merging
    $StartingMergeStrategy = Get-MergeStrategyFromPath -PropertyPath $PropertyPath -Strategies $options

    # Walk every search path in listed order, and return datum when found at end of path
    foreach ($SearchPrefix in $PathPrefixes) {
        #through the hierarchy

        $ArraySb = [System.Collections.ArrayList]@()
        $CurrentSearch = [System.IO.Path]::Combine($SearchPrefix, $PropertyPath)
        #$CurrentSearch = Join-Path $SearchPrefix $PropertyPath
        Write-Verbose ''
        Write-Verbose " Lookup <$CurrentSearch> $($Node.Name)"
        #extract script block for execution into array, replace by substition strings {0},{1}...
        $newSearch = [regex]::Replace($CurrentSearch, $Pattern, {
                param($match)
                $expr = $match.groups['sb'].value
                $index = $ArraySb.Add($expr)
                "`$({$index})"
            }, @('IgnoreCase', 'SingleLine', 'MultiLine'))

        $PathStack = $newSearch -split $splitPattern
        # Get value for this property path
        $DatumFound = Resolve-DatumPath -Node $Node -DatumTree $DatumTree -PathStack $PathStack -PathVariables $ArraySb

        if ($DatumFound -is [DatumProvider]) {
            $DatumFound = $DatumFound.ToOrderedHashTable()
        }

        Write-Debug "  Depth: $depth; Merge options = $($options.count)"

        #Stop processing further path at first value in 'MostSpecific' mode (called 'first' in Puppet hiera)
        if ($null -ne $DatumFound -and ($StartingMergeStrategy.Strategy -match '^MostSpecific|^First')) {
            return $DatumFound
        }
        elseif ($null -ne $DatumFound) {

            if ($null -eq $MergeResult) {
                $MergeResult = $DatumFound
            }
            else {
                $MergeParams = @{
                    StartingPath    = $PropertyPath
                    ReferenceDatum  = $MergeResult
                    DifferenceDatum = $DatumFound
                    Strategies      = $options
                }
                $MergeResult = Merge-Datum @MergeParams
            }
        }

        #if we've reached the Maximum Depth allowed, return current result and stop further execution
        if ($Depth -eq $MaxDepth) {
            Write-Debug "  Max depth of $MaxDepth reached. Stopping."
            ,$MergeResult
            return
        }
    }
    ,$MergeResult
}
#EndRegion './Public/Resolve-Datum.ps1' 210
#Region './Public/Resolve-DatumPath.ps1' 0
function Resolve-DatumPath {
    [CmdletBinding()]
    param(
        [Alias('Variable')]
        $Node,

        [Alias('DatumStructure')]
        $DatumTree,

        [string[]]
        $PathStack,

        [System.Collections.ArrayList]
        $PathVariables
    )

    $currentNode = $DatumTree
    $PropertySeparator = '.' #[io.path]::DirectorySeparatorChar
    $index = -1
    Write-Debug "`t`t`t"

    foreach ($StackItem in $PathStack) {
        $index++
        $RelativePath = $PathStack[0..$index]
        Write-Debug "`t`t`tCurrent Path: `$Datum$PropertySeparator$($RelativePath -join $PropertySeparator)"
        $RemainingStack = $PathStack[$index..($PathStack.Count-1)]
        Write-Debug "`t`t`t`tbranch of path Left to walk: $PropertySeparator$($RemainingStack[1..$RemainingStack.Length] -join $PropertySeparator)"
        if ( $StackItem -match '\{\d+\}') {
            Write-Debug -Message "`t`t`t`t`tReplacing expression $StackItem"
            $StackItem = [scriptblock]::Create( ($StackItem -f ([string[]]$PathVariables)) ).Invoke()
            Write-Debug -Message ($StackItem | Format-List * | Out-String)
            $PathItem = $stackItem
        }
        else {
            $PathItem = $CurrentNode.($ExecutionContext.InvokeCommand.ExpandString($StackItem))
        }

        # if $PathItem is $null, it won't have subkeys, stop execution for this Prefix
        if($null -eq $PathItem) {
            Write-Verbose -Message " NULL FOUND at `$Datum.$($ExecutionContext.InvokeCommand.ExpandString(($RelativePath -join $PropertySeparator) -f [string[]]$PathVariables))`t`t <`$Datum$PropertySeparator$(($RelativePath -join $PropertySeparator) -f [string[]]$PathVariables)>"
            if($RemainingStack.Count -gt 1) {
                Write-Verbose -Message "`t`t----> before:  $propertySeparator$($ExecutionContext.InvokeCommand.ExpandString(($RemainingStack[1..($RemainingStack.Count-1)] -join $PropertySeparator)))`t`t <$(($RemainingStack[1..($RemainingStack.Count-1)] -join $PropertySeparator) -f [string[]]$PathVariables)>"
            }
            Return $null
        }
        else {
            $CurrentNode = $PathItem
        }


        if ($RemainingStack.Count -eq 1) {
            Write-Verbose -Message " VALUE found at `$Datum$PropertySeparator$($ExecutionContext.InvokeCommand.ExpandString(($RelativePath -join $PropertySeparator) -f [string[]]$PathVariables))"
            ,$CurrentNode
        }

    }
}
#EndRegion './Public/Resolve-DatumPath.ps1' 58
#Region './Public/Test-TestHandlerFilter.ps1' 0
function Test-TestHandlerFilter {
    Param(
        [Parameter(
            ValueFromPipeline
        )]
        $inputObject
    )

    $InputObject -is [string] -and $InputObject -match "^\[TEST=[\w\W]*\]$"
}
#EndRegion './Public/Test-TestHandlerFilter.ps1' 11

function Clone-Object {
    param(
        [object]$DeepCopyObject
    )
   
    $serialData = [System.Management.Automation.PSSerializer]::Serialize($DeepCopyObject)
    [System.Management.Automation.PSSerializer]::Deserialize($serialData)
}