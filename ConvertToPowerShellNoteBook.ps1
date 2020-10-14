function ConvertTo-PowerShellNoteBook {
    <#
        .Example
        ConvertTo-PowerShellNoteBook -InputFileName c:\Temp\demo.txt -OutputNotebookName c:\Temp\demo.ipynb
    #>
    param(
        $InputFileName,
        $OutputNotebookName
    )
    <#################################################################################################
    Parsing section.
    #################################################################################################>

    if ([System.Uri]::IsWellFormedUriString($InputFileName, [System.UriKind]::Absolute)) {    
        $s = Invoke-RestMethod -Uri $InputFileName
    }
    else {
        $s = Get-Content -Raw ( Resolve-Path $InputFileName )
    }

    try {
        # $CommentRanges = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $InputFileName), [ref]$null).Where( { $_.Type -eq 'Comment' }) |
        $CommentRanges = [System.Management.Automation.PSParser]::Tokenize($s, [ref]$null).Where( { $_.Type -eq 'Comment' }) |
        Select-Object -Property Start, Length, Type, Content 
    }
    Catch {
        "This is not a valid PowerShell file" 
    }    
    
    $BlocksWitGaps = @()
    $Previous = $null
    foreach ($CommentBlock in $CommentRanges ) {
        $BlockOffsets = [ordered]@{
            Start              = $CommentBlock.Start;
            StopOffset         = $CommentBlock.Start + $CommentBlock.Length;
            Length             = $CommentBlock.Length;
            GapLength          = [int] $CommentBlock.Start - $Previous.StopOffset;
            PreviousStart      = $Previous.Start;
            PreviousStopOffset = $Previous.StopOffset;
            Type               = 'Code';
            GapText            = IF ($CommentBlock.Start - $Previous.StopOffset -gt 1) { [string] $s.Substring($Previous.StopOffset, ($CommentBlock.Start - $Previous.StopOffset)).trimstart() }else { [string] '' };
            Content            = $CommentBlock.Content
        }
    
        $Previous = $BlockOffsets
        $BlocksWitGaps += [pscustomobject] $BlockOffsets
    }
    
    
    $AllBlocks = @()
    $Previous = $null
    $AllBlocks = $CommentRanges
    <# Catch anything missed from the tail of the file, add it to $AllBlocks #>
    if ($BlocksWitGaps.Count -eq 1) {
        <# This step handles ading the psobjects together if $CommentBlock isn't an array. #>
        $AllBlocks = @($CommentBlock; [pscustomobject][Ordered]@{
                Start   = ($CommentBlock.Start + $CommentBlock.Length);
                Length  = $s.Length - ($CommentBlock.Start + $CommentBlock.Length);
                Type    = 'Gap';
                Content = $s.Substring(($CommentBlock.Start + $CommentBlock.Length), ($s.Length - ($CommentBlock.Start + $CommentBlock.Length))).trimstart()
            })
    }
    else {
        if (($CommentBlock.Start + $CommentBlock.Length) -lt $s.Length) {
            $AllBlocks += [pscustomobject][ordered]@{
                Start   = ($CommentBlock.Start + $CommentBlock.Length);
                Length  = $s.Length - ($CommentBlock.Start + $CommentBlock.Length);
                Type    = 'Gap';
                Content = $s.Substring(($CommentBlock.Start + $CommentBlock.Length), ($s.Length - ($CommentBlock.Start + $CommentBlock.Length))).trimstart()
            }
        }
    }
    
    foreach ($GapBlock in $BlocksWitGaps ) {
        $GapOffsets = [ordered]@{
            Start      = $GapBlock.PreviousStopOffset;
            StopOffset = $GapBlock.Start;
            Length     = $GapBlock.GapLength;
            Type       = 'Gap';
            Content    = $GapBlock.GapText.trimstart()
        }
    
        $Previous = $GapOffsets
        $AllBlocks += if ($GapOffsets.Length -gt 0) { [pscustomobject] $GapOffsets }
    }
    
    <#################################################################################################
    Notebook creation section.
    #################################################################################################>    
    
    New-PSNotebook -NoteBookName $OutputNotebookName {
    
        foreach ($Block in $AllBlocks | Sort-Object Start ) {
    
            
            switch ($Block.Type) {
                'Comment' {
                    $TextBlock = $s.Substring($Block.Start, $Block.Length) -replace ("\n", "   `n  ")
    
                    if ($TextBlock.Trim().length -gt 0) {
                        Add-NotebookMarkdown -markdown (-join $TextBlock)
                    }
                }
                'Gap' {
                    $GapBlock = $s.Substring($Block.Start, $Block.Length)
    
                    if ($GapBlock.Trim().length -gt 0) {
                        Add-NotebookCode -code (-join $GapBlock.trimstart().trimend()) -replace ("\n", "   `n  ")
                    }
                }
            }
    
        }
    }
}