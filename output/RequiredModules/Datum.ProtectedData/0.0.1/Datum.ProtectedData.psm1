function Invoke-ProtectedDatumAction {
    <#
    .SYNOPSIS
    Action that decrypt the secret when the Datum Handler is triggered

    .DESCRIPTION
    When Datum uses this handler and a piece of data pass the associated filter, this
    action will decrypt the data.

    .PARAMETER InputObject
    Datum data to be decrypted

    .PARAMETER PlainTextPassword
    !! FOR TESTING ONLY!!
    Plain text password used for decrypting the password when you want to easily test.
    You can configure the password in the Datum.yml file in the DatumHandler section when
    doing tests.

    .PARAMETER Certificate
    Provide the Certificate in a format supported by Dave Wyatt's ProtectedData module:
    It can be a thumbprint, certificate file, path to a certificate file or to cert provider...

    .PARAMETER Header
    Header of the Datum data string that encapsulates the encrypted data. The default is [ENC= but can be
    customized (i.e. in the Datum.yml configuration file)

    .PARAMETER Footer
    Footer of the Datum data string that encapsulates the encrypted data. The default is ]

    .EXAMPLE
    $objectToDecrypt | Invoke-ProtectedDatumAction

    .NOTES
    The arguments you can set in the Datum.yml is directly related to the arguments of this function.

    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText','')]
    Param (
        # Serialized Protected Data represented on Base64 encoding
        [Parameter(
            Mandatory
            , Position = 0
            , ValueFromPipeline
            , ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [string]
        $InputObject,

        # By Password only for development / Test purposes
        [Parameter(
            ParameterSetName = 'ByPassword'
            , Mandatory
            , Position = 1
            , ValueFromPipelineByPropertyName
        )]
        [String]
        $PlainTextPassword,

        # Specify the Certificate to be used by ProtectedData
        [Parameter(
            ParameterSetName = 'ByCertificate'
            , Mandatory
            , Position = 1
            , ValueFromPipelineByPropertyName
        )]
        [String]
        $Certificate,

        # Number of columns before inserting newline in chunk
        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [String]
        $Header = '[ENC=',

        # Number of columns before inserting newline in chunk
        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [String]
        $Footer = ']'
    )

    Write-Error "ProtectedData Error"

    Write-Debug "Decrypting Datum using ProtectedData"
    $params = @{}
    foreach ($ParamKey in $PSBoundParameters.keys) {
        if ($ParamKey -in @('InputObject', 'PlainTextPassword')) {
            switch ($ParamKey) {
                'PlainTextPassword' { $params.add('password', (ConvertTo-SecureString -AsPlainText -Force $PSBoundParameters[$ParamKey])) }
                'InputObject' { $params.add('Base64Data', $InputObject) }
            }
        }
        else {
            $params.add($ParamKey, $PSBoundParameters[$ParamKey])
        }
    }

    UnProtect-Datum @params

}

#Requires -Modules ProtectedData

function Protect-Datum {
    <#
    .SYNOPSIS
    Protects an object into an encrypted string ready to use in a text file (yaml, JSON, PSD1)

    .DESCRIPTION
    This command will serialize (i.e. Export-CLIXml) and object, base 64 encode it and then encrypt
    so that it can be used as a string in a text-based file, like a Datum config file.

    .PARAMETER InputObject
    The object to provide to be encrypted and secured.

    .PARAMETER Password
    ! FOR TESTING ONLY! Password to encrypt the data.

    .PARAMETER Certificate
    Certificate as supported by Dave Wyatt's ProtectedData module: Certificate File, thumbprint, path to file...

    .PARAMETER MaxLineLength
    Allow to format somehow the line so that the blob of text is spread on several lines.

    .PARAMETER Header
    Adds an encapsulation Header, [ENC= by default

    .PARAMETER Footer
    Adds an encapsulation footer, ] by default

    .PARAMETER NoEncapsulation
    Generate the encrypted data block without encapsulating with header/footer.
    Useful to test.

    .EXAMPLE
    Protect-Datum -InputObject $credential -Password P@ssw0rd

    .NOTES
    This function is a helper to build your file containing a secret.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    Param (
        # Serialized Protected Data represented on Base64 encoding
        [Parameter(
            Mandatory
            , Position = 0
            , ValueFromPipeline
            , ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [PSObject]
        $InputObject,

        # By Password only for development / Test purposes
        [Parameter(
            ParameterSetName = 'ByPassword'
            , Mandatory
            , Position = 1
            , ValueFromPipelineByPropertyName
        )]
        [System.Security.SecureString]
        $Password,

        # Specify the Certificate to be used by ProtectedData
        [Parameter(
            ParameterSetName = 'ByCertificate'
            , Mandatory
            , Position = 1
            , ValueFromPipelineByPropertyName
        )]
        [String]
        $Certificate,

        # Number of columns before inserting newline in chunk
        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [Int]
        $MaxLineLength = 100,

        # Number of columns before inserting newline in chunk
        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [String]
        $Header = '[ENC=',

        # Number of columns before inserting newline in chunk
        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [String]
        $Footer = ']',

        # Number of columns before inserting newline in chunk
        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [Switch]
        $NoEncapsulation

    )

    begin {
    }

    process {
        Write-Verbose "Deserializing the Object from Base64"

        $ProtectDataParams = @{
            InputObject = $InputObject
        }
        Write-verbose "Calling Protect-Data $($PSCmdlet.ParameterSetName)"
        Switch ($PSCmdlet.ParameterSetName) {
            'ByCertificate' { $ProtectDataParams.Add('Certificate', $Certificate)}
            'ByPassword' { $ProtectDataParams.Add('Password', $Password)      }
        }

        $securedData = Protect-Data @ProtectDataParams
        $xml = [System.Management.Automation.PSSerializer]::Serialize($securedData, 5)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
        $Base64String = [System.Convert]::ToBase64String($bytes)

        if ($MaxLineLength -gt 0) {
            $Base64DataBlock = [regex]::Replace($Base64String, "(.{$MaxLineLength})", "`$1`r`n")
        }
        else {
            $Base64DataBlock = $Base64String
        }
        if (!$NoEncapsulation) {
            $Header, $Base64DataBlock, $Footer -join ''
        }
        else {
            $Base64DataBlock
        }
    }
}

function Test-ProtectedDatumFilter {
    <#
    .SYNOPSIS
    Filter function to verify if it's worth triggering the action for the data block.

    .DESCRIPTION
    This function is run in the ConvertTo-Datum function of the Datum module on every pass,
    and when it returns true, the action of the handler is called.

    .PARAMETER InputObject
    Object to test to decide whether to trigger the action or not

    .EXAMPLE
    $object | Test-ProtectedDatumFilter

    #>
    Param(
        [Parameter(
            ValueFromPipeline
        )]
        $InputObject
    )

    $InputObject -is [string] -and $InputObject.Trim() -match "^\[ENC=[\w\W]*\]$"
}

#Requires -Modules ProtectedData

function Unprotect-Datum {
    <#
    .SYNOPSIS
    Decrypt a previously encrypted object

    .DESCRIPTION
    This command decrypts the string representation of an object previously encrypted
    by Protect-Datum. You can decrypt a credential object, a secure string or simply
    a string. It uses Dave Wyatt's ProtectedData module under the hood.

    .PARAMETER Base64Data
    The encrypted data is represented in a Base 64 string to be easily stored in a text document.
    This is the input to be decrypted and restored as an object.

    .PARAMETER Password
    ! FOR TESTS ONLY !
    You can use a password to encrypt and decrypt the data you want to secure when doing test
    with this module

    .PARAMETER Certificate
    You can pass the certificate (thumbprint, file, file path, cert provider path...) containing the
    private key to be used to decrypt the secured data.

    .PARAMETER Header
    Header to strip off when encapsulated in a file. default is [ENC=

    .PARAMETER Footer
    Footer to strip off when encapsulated in a file. default is ]

    .PARAMETER NoEncapsulation
    Switch to attempt the decryption when there is no encapsulation

    .EXAMPLE
    $encryptedstring | Unprotect-Datum -NoEncapsulation -Password P@ssw0rd

    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    Param (
        # Serialized Protected Data represented on Base64 encoding
        [Parameter(
            Mandatory
            , Position = 0
            , ValueFromPipeline
            , ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [string]
        $Base64Data,

        # By Password only for development / Test purposes
        [Parameter(
            ParameterSetName = 'ByPassword'
            , Mandatory
            , Position = 1
            , ValueFromPipelineByPropertyName
        )]
        [System.Security.SecureString]
        $Password,

        # Specify the Certificate to be used by ProtectedData
        [Parameter(
            ParameterSetName = 'ByCertificate'
            , Mandatory
            , Position = 1
            , ValueFromPipelineByPropertyName
        )]
        [String]
        $Certificate,

        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [String]
        $Header = '[ENC=',

        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [String]
        $Footer = ']',

        [Parameter(
            ValueFromPipelineByPropertyName
        )]
        [Switch]
        $NoEncapsulation
    )

    begin {
    }

    process {
        if (!$NoEncapsulation) {
            Write-Verbose "Removing $header DATA $footer "
            $Base64Data = $Base64Data -replace "^$([regex]::Escape($Header))" -replace "$([regex]::Escape($Footer))$"
        }

        Write-Verbose "Deserializing the Object from Base64"
        $bytes = [System.Convert]::FromBase64String($Base64Data)
        $xml = [System.Text.Encoding]::UTF8.GetString($bytes)
        $obj = [System.Management.Automation.PSSerializer]::Deserialize($xml)
        $UnprotectDataParams = @{
            InputObject = $obj
        }
        Write-verbose "Calling Unprotect-Data $($PSCmdlet.ParameterSetName)"
        Switch ($PSCmdlet.ParameterSetName) {
            'ByCertificae' { $UnprotectDataParams.Add('Certificate', $Certificate)}
            'ByPassword' { $UnprotectDataParams.Add('Password', $Password)      }
        }
        Unprotect-Data @UnprotectDataParams
    }

}
