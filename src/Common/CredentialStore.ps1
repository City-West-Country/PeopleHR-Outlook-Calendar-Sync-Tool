# Windows Credential Manager access via advapi32 P/Invoke — no external modules required.
# Secrets are stored as CRED_TYPE_GENERIC credentials with LOCAL_MACHINE persistence, so a
# scheduled task running as the SAME user account can read them whether or not that user is
# interactively logged on. Credentials are NOT shared across user accounts.

if (-not ([System.Management.Automation.PSTypeName]'PhrCredentialStore').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class PhrCredentialStore
{
    const uint CRED_TYPE_GENERIC = 1;
    const uint CRED_PERSIST_LOCAL_MACHINE = 2;
    const int  ERROR_NOT_FOUND = 1168;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct NativeCredential
    {
        public uint Flags;
        public uint Type;
        [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
        [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
        public long LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;
        [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredWrite(ref NativeCredential credential, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredRead(string target, uint type, uint flags, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredFree")]
    static extern void CredFree(IntPtr buffer);

    public static void Write(string target, string userName, string secret)
    {
        byte[] bytes = Encoding.Unicode.GetBytes(secret ?? string.Empty);
        if (bytes.Length > 2560)
            throw new ArgumentException("Credential secret exceeds the 2560-byte Credential Manager limit.");

        IntPtr blob = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, blob, bytes.Length);
        try
        {
            var cred = new NativeCredential
            {
                Type = CRED_TYPE_GENERIC,
                TargetName = target,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = CRED_PERSIST_LOCAL_MACHINE,
                UserName = string.IsNullOrEmpty(userName) ? target : userName
            };
            if (!CredWrite(ref cred, 0))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        finally { Marshal.FreeHGlobal(blob); }
    }

    public static string Read(string target)
    {
        IntPtr credPtr;
        if (!CredRead(target, CRED_TYPE_GENERIC, 0, out credPtr))
        {
            int err = Marshal.GetLastWin32Error();
            if (err == ERROR_NOT_FOUND) return null;
            throw new System.ComponentModel.Win32Exception(err);
        }
        try
        {
            var cred = (NativeCredential)Marshal.PtrToStructure(credPtr, typeof(NativeCredential));
            if (cred.CredentialBlobSize == 0) return string.Empty;
            byte[] bytes = new byte[cred.CredentialBlobSize];
            Marshal.Copy(cred.CredentialBlob, bytes, 0, (int)cred.CredentialBlobSize);
            return Encoding.Unicode.GetString(bytes);
        }
        finally { CredFree(credPtr); }
    }

    public static bool Delete(string target)
    {
        if (!CredDelete(target, CRED_TYPE_GENERIC, 0))
        {
            int err = Marshal.GetLastWin32Error();
            if (err == ERROR_NOT_FOUND) return false;
            throw new System.ComponentModel.Win32Exception(err);
        }
        return true;
    }
}
'@
}

function Get-SyncCredentialTarget {
    <#
    .SYNOPSIS
        Returns the Windows Credential Manager target name for a logical secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ClientSecret', 'ApiKey')]
        [string]$For
    )
    switch ($For) {
        'ClientSecret' { 'PeopleHrSync:GraphClientSecret' }
        'ApiKey'       { 'PeopleHrSync:PeopleHrApiKey' }
    }
}

function Set-SyncCredential {
    <#
    .SYNOPSIS
        Stores a secret in Windows Credential Manager for the current user.

    .PARAMETER For
        Logical secret name ('ClientSecret' or 'ApiKey').

    .PARAMETER Secret
        The secret value, as a plain string or a SecureString.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateSet('ClientSecret', 'ApiKey')] [string]$For,
        [Parameter(Mandatory)] $Secret
    )

    $target = Get-SyncCredentialTarget -For $For

    if ($Secret -is [securestring]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
        try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    else {
        $plain = [string]$Secret
    }

    if ($PSCmdlet.ShouldProcess($target, 'Write credential')) {
        [PhrCredentialStore]::Write($target, "PeopleHrSync ($env:USERNAME)", $plain)
    }
}

function Get-SyncCredential {
    <#
    .SYNOPSIS
        Reads a stored secret from Windows Credential Manager. Returns $null if absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('ClientSecret', 'ApiKey')] [string]$For
    )
    $target = Get-SyncCredentialTarget -For $For
    try { return [PhrCredentialStore]::Read($target) }
    catch {
        Write-Verbose "Credential read failed for '$target': $($_.Exception.Message)"
        return $null
    }
}

function Test-SyncCredential {
    <#
    .SYNOPSIS
        Returns $true if a non-empty secret is stored for the given logical name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('ClientSecret', 'ApiKey')] [string]$For
    )
    return -not [string]::IsNullOrEmpty((Get-SyncCredential -For $For))
}

function Remove-SyncCredential {
    <#
    .SYNOPSIS
        Deletes a stored secret from Windows Credential Manager. Returns $true if removed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateSet('ClientSecret', 'ApiKey')] [string]$For
    )
    $target = Get-SyncCredentialTarget -For $For
    if ($PSCmdlet.ShouldProcess($target, 'Delete credential')) {
        return [PhrCredentialStore]::Delete($target)
    }
}
