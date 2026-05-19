param (
    [string]$InputJsonPath = "C:\Users\UltraPc\Desktop\Output\Exports\Marvel\Content\Marvel\Characters\1048\1048001\Meshes\Game.json",
    [string]$OutputTxtPath = "C:\Users\UltraPc\Desktop\Output\Exports\AnimBPs_Output.txt"
)

[System.Threading.Thread]::CurrentThread.CurrentCulture = 'en-US'

$raw = Get-Content -Raw -Path $InputJsonPath | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Find the Properties bag that contains AnimGraph nodes
# ---------------------------------------------------------------------------
$props = $null

if ($raw -is [System.Array]) {
    foreach ($obj in $raw) {
        if ($obj.Properties) {
            $hasNodes = $obj.Properties.PSObject.Properties.Name | Where-Object { $_ -like "AnimGraphNode_*" }
            if ($hasNodes) {
                Write-Host "Found AnimGraph nodes in: Type=$($obj.Type)  Name=$($obj.Name)"
                $props = $obj.Properties
                break
            }
        }
    }
} elseif ($raw.PSObject.Properties.Name -contains "Properties") {
    $props = $raw.Properties
} else {
    $props = $raw
}

if (-not $props) {
    Write-Host "Could not find any AnimGraph node properties in the JSON."
    exit 1
}

Write-Host "`nAll AnimGraph node keys found:"
$props.PSObject.Properties.Name | Where-Object { $_ -like "AnimGraphNode_*" } | ForEach-Object { Write-Host "  $_" }
Write-Host ""

$output = @()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Format-Float($val) {
    return "{0:F6}" -f [double]$val
}

function New-Guid {
    return [System.Guid]::NewGuid().ToString("N").ToUpper()
}

function Format-CurveKeys {
    param ($curve)
    if ($curve -and $curve.EditorCurveData -and $curve.EditorCurveData.Keys.Count -gt 0) {
        $keyStrings = $curve.EditorCurveData.Keys | ForEach-Object {
            "(Time={0},Value={1})" -f (Format-Float $_.Time), (Format-Float $_.Value)
        }
        return "EditorCurveData=(Keys=({0}))" -f ($keyStrings -join ",")
    }
    return $null
}

function Format-ExternalLimits {
    param ($limits, $type)
    if ($limits -and $limits.Count -gt 0) {
        $formatted = $limits | ForEach-Object {
            $r    = Format-Float $_.Radius
            $l    = Format-Float $_.Length
            $bone = $_.DrivingBone.BoneName
            $ol   = $_.OffsetLocation
            $or_  = $_.OffsetRotation
            "(Radius=$r,Length=$l,DrivingBone=(BoneName=""$bone""),OffsetLocation=(X={0},Y={1},Z={2}),OffsetRotation=(Pitch={3},Yaw={4},Roll={5}))" -f `
                (Format-Float $ol.X), (Format-Float $ol.Y), (Format-Float $ol.Z),
                (Format-Float $or_.Pitch), (Format-Float $or_.Yaw), (Format-Float $or_.Roll)
        }
        return "$type=({0})" -f ($formatted -join ",")
    }
    return $null
}

function Format-LimitsDataAsset {
    param ($asset)
    if ($asset -and $asset.ObjectPath) {
        $path      = $asset.ObjectPath -replace "\.0$", ""
        $shortName = ($asset.ObjectName -split "'")[-2]
        return 'LimitsDataAsset="/Script/KawaiiPhysics.KawaiiPhysicsLimitsDataAsset''' + $path + '.' + $shortName + '''"'
    }
    return $null
}

# ---------------------------------------------------------------------------
# Format a single Chain entry
# ---------------------------------------------------------------------------
function Format-Chain {
    param ($chain)

    $bs = $chain.BoneSettings
    $ps = $chain.PhysicsSettings

    $rootBone        = $bs.RootBone.BoneName
    $dummyBoneLength = Format-Float $bs.DummyBoneLength
    $boneAxis        = ($bs.BoneForwardAxis -split "::")[-1]

    $excludePart = ""
    if ($bs.ExcludeBones -and $bs.ExcludeBones.Count -gt 0) {
        $ex = $bs.ExcludeBones | ForEach-Object { '(BoneName="{0}")' -f $_.BoneName }
        $excludePart = ",ExcludeBones=({0})" -f ($ex -join ",")
    }

    $arbPart = ""
    if ($bs.AdditionalRootBones -and $bs.AdditionalRootBones.Count -gt 0) {
        $parts = $bs.AdditionalRootBones | ForEach-Object { "(RootBone=(BoneName=""{0}""))" -f $_.RootBone.BoneName }
        $arbPart = ",AdditionalRootBones=({0})" -f ($parts -join ",")
    }

    $rootSimFlag = if ($bs.bRootBoneSimulate)  { ",bRootBoneSimulate=True"  } else { "" }
    $fixTailFlag = if ($bs.bShouldFixTailBone) { ",bShouldFixTailBone=True" } else { "" }

    $fixedBonePart  = ""
    $followBonePart = ""
    if ($bs.FixedBone  -and $bs.FixedBone.BoneName  -ne "None") { $fixedBonePart  = ",FixedBone=(BoneName=""{0}"")"  -f $bs.FixedBone.BoneName }
    if ($bs.FollowBone -and $bs.FollowBone.BoneName -ne "None") { $followBonePart = ",FollowBone=(BoneName=""{0}"")" -f $bs.FollowBone.BoneName }

    $inner = $ps.PhysicsSettings
    $physicsString = ""
    if ($inner) {
        $physicsString = "Damping={0},Stiffness={1},WorldDampingLocation={2},WorldDampingRotation={3},Radius={4},LimitAngle={5},LimitLinear={6},GravityScale={7}" -f `
            (Format-Float $inner.Damping), (Format-Float $inner.Stiffness),
            (Format-Float $inner.WorldDampingLocation), (Format-Float $inner.WorldDampingRotation),
            (Format-Float $inner.Radius), (Format-Float $inner.LimitAngle),
            (Format-Float $inner.LimitLinear), (Format-Float $inner.GravityScale)
    }

    $tpdist   = Format-Float $ps.TeleportDistanceThreshold
    $tprotate = Format-Float $ps.TeleportRotationThreshold
    $planar   = ($ps.PlanarConstraint -split "::")[-1]
    $useCurve = if ($ps.bUseCurve) { ",bUseCurve=True" } else { "" }

    $curveParts = @()
    foreach ($curveName in @(
        "DampingCurveData","StiffnessCurveData",
        "WorldDampingLocationCurveData","WorldDampingRotationCurveData",
        "RadiusCurveData","LimitAngleCurveData","LimitLinearCurveData","GravityCurveData"
    )) {
        if ($ps.$curveName) {
            $c = Format-CurveKeys $ps.$curveName
            if ($c) { $curveParts += "$curveName=($c)" }
        }
    }

    $customShapesPart = ""
    if ($ps.CustomShapes -and $ps.CustomShapes.Count -gt 0) {
        $shapes = $ps.CustomShapes | ForEach-Object {
            $sbone = $_.DrivingBone.BoneName
            $stype = ($_.ShapeType -split "::")[-1]
            $halfH = Format-Float $_.HalfHeight
            $sor   = $_.OffsetRotation
            "(DrivingBone=(BoneName=""$sbone""),ShapeType=$stype,HalfHeight=$halfH,OffsetRotation=(Pitch={0},Yaw={1},Roll={2}))" -f `
                (Format-Float $sor.Pitch), (Format-Float $sor.Yaw), (Format-Float $sor.Roll)
        }
        $customShapesPart = ",CustomShapes=({0})" -f ($shapes -join ",")
    }

    $curveExtra = if ($curveParts.Count -gt 0) { "," + ($curveParts -join ",") } else { "" }

    $bcs      = $chain.BoneConstraintSettings
    $comptype = if ($bcs -and $bcs.BoneConstraintGlobalComplianceType) { ($bcs.BoneConstraintGlobalComplianceType -split "::")[-1] } else { "" }

    $boneSettingsStr   = "(RootBone=(BoneName=""$rootBone"")$excludePart$arbPart$rootSimFlag$fixTailFlag$fixedBonePart$followBonePart,DummyBoneLength=$dummyBoneLength,BoneForwardAxis=$boneAxis)"
    $physSettingsStr   = "(PhysicsSettings=($physicsString),TeleportDistanceThreshold=$tpdist,TeleportRotationThreshold=$tprotate,PlanarConstraint=$planar$useCurve$customShapesPart$curveExtra)"
    $boneConstraintStr = "(BoneConstraintGlobalComplianceType=$comptype)"

    return "(BoneSettings=$boneSettingsStr,PhysicsSettings=$physSettingsStr,BoneConstraintSettings=$boneConstraintStr)"
}

# ---------------------------------------------------------------------------
# KawaiiPhysics node formatter with pin linking
# ---------------------------------------------------------------------------
function Format-KawaiiPhysicsNode {
    param ($key, $node, $index, $inGuid, $outGuid, $prevName, $prevOutGuid, $nextName, $nextInGuid)

    $chainStrings = @()
    foreach ($chain in $node.Chains) {
        $chainStrings += Format-Chain $chain
    }
    $chainsPart = "Chains=({0})" -f ($chainStrings -join ",")

    $extraParts = @()
    foreach ($limitType in @("CapsuleLimits","BoxLimits","PlanarLimits","SphericalLimits")) {
        if ($node.$limitType -and $node.$limitType.Count -gt 0) {
            $c = Format-ExternalLimits $node.$limitType $limitType
            if ($c) { $extraParts += $c }
        }
    }
    if ($node.LimitsDataAsset) {
        $lda = Format-LimitsDataAsset $node.LimitsDataAsset
        if ($lda) { $extraParts += $lda }
    }

    $extra = if ($extraParts.Count -gt 0) { "," + ($extraParts -join ",") } else { "" }

    $row  = $index % 10
    $col  = [math]::Floor($index / 10)
    $posX = $col * 400
    $posY = $row * 144

    # Build LinkedTo parts
    $inLinkedTo  = if ($prevName) { ",LinkedTo=($prevName $prevOutGuid)" } else { "" }
    $outLinkedTo = if ($nextName) { ",LinkedTo=($nextName $nextInGuid)"  } else { "" }

    return @"
Begin Object Class=/Script/KawaiiPhysicsEd.AnimGraphNode_KawaiiPhysics Name="$key"
   Node=($chainsPart$extra)
   ShowPinForProperties(0)=(PropertyName="ComponentPose",bShowPin=True)
   ShowPinForProperties(1)=(PropertyName="bAlphaBoolEnabled",bShowPin=True)
   ShowPinForProperties(2)=(PropertyName="Alpha",bShowPin=True)
   ShowPinForProperties(3)=(PropertyName="AlphaCurveName",bShowPin=True)
   NodePosX=$posX
   NodePosY=$posY
   CustomProperties Pin (PinId=$inGuid,PinName="ComponentPose",PinFriendlyName="Component Pose",PinType.PinCategory="struct",PinType.PinSubCategoryObject="/Script/Engine.ComponentSpacePoseLink"$inLinkedTo)
   CustomProperties Pin (PinId=$outGuid,PinName="Pose",Direction="EGPD_Output",PinType.PinCategory="struct",PinType.PinSubCategoryObject="/Script/Engine.ComponentSpacePoseLink"$outLinkedTo)
End Object
"@
}

# ---------------------------------------------------------------------------
# ModifyBone node formatter
# ---------------------------------------------------------------------------
function Format-ModifyBoneNode {
    param ($key, $node, $index, $inGuid, $outGuid, $prevName, $prevOutGuid, $nextName, $nextInGuid)

    $bone   = $node.BoneToModify.BoneName
    $t      = $node.Translation
    $r      = $node.Rotation
    $s      = $node.Scale
    $tmode  = ($node.TranslationMode  -split "::")[-1]
    $rmode  = ($node.RotationMode     -split "::")[-1]
    $smode  = ($node.ScaleMode        -split "::")[-1]
    $tspace = ($node.TranslationSpace -split "::")[-1]
    $rspace = ($node.RotationSpace    -split "::")[-1]
    $sspace = ($node.ScaleSpace       -split "::")[-1]

    $row  = $index % 10
    $col  = [math]::Floor($index / 10)
    $posX = $col * 400
    $posY = $row * 144

    $inLinkedTo  = if ($prevName) { ",LinkedTo=($prevName $prevOutGuid)" } else { "" }
    $outLinkedTo = if ($nextName) { ",LinkedTo=($nextName $nextInGuid)"  } else { "" }

    return @"
Begin Object Class=/Script/AnimGraph.AnimGraphNode_ModifyBone Name="$key"
   Node=(BoneToModify=(BoneName="$bone"),Translation=(X=$(Format-Float $t.X),Y=$(Format-Float $t.Y),Z=$(Format-Float $t.Z)),Rotation=(Pitch=$(Format-Float $r.Pitch),Yaw=$(Format-Float $r.Yaw),Roll=$(Format-Float $r.Roll)),Scale=(X=$(Format-Float $s.X),Y=$(Format-Float $s.Y),Z=$(Format-Float $s.Z)),TranslationMode=$tmode,RotationMode=$rmode,ScaleMode=$smode,TranslationSpace=$tspace,RotationSpace=$rspace,ScaleSpace=$sspace)
   ShowPinForProperties(0)=(PropertyName="ComponentPose",bShowPin=True)
   ShowPinForProperties(1)=(PropertyName="bAlphaBoolEnabled",bShowPin=True)
   ShowPinForProperties(2)=(PropertyName="Alpha",bShowPin=True)
   ShowPinForProperties(3)=(PropertyName="AlphaCurveName",bShowPin=True)
   NodePosX=$posX
   NodePosY=$posY
   CustomProperties Pin (PinId=$inGuid,PinName="ComponentPose",PinFriendlyName="Component Pose",PinType.PinCategory="struct",PinType.PinSubCategoryObject="/Script/Engine.ComponentSpacePoseLink"$inLinkedTo)
   CustomProperties Pin (PinId=$outGuid,PinName="Pose",Direction="EGPD_Output",PinType.PinCategory="struct",PinType.PinSubCategoryObject="/Script/Engine.ComponentSpacePoseLink"$outLinkedTo)
End Object
"@
}

# ---------------------------------------------------------------------------
# Constraint node formatter
# ---------------------------------------------------------------------------
function Format-ConstraintNode {
    param ($key, $node, $index, $inGuid, $outGuid, $prevName, $prevOutGuid, $nextName, $nextInGuid)

    $bone = $node.BoneToModify.BoneName
    $setupEntries = $node.ConstraintSetup | ForEach-Object {
        $targetBone = $_.TargetBone.BoneName
        $offset     = ($_.OffsetOption  -split "::")[-1]
        $ttype      = ($_.TransformType -split "::")[-1]
        $px = $_.PerAxis.bX.ToString().ToLower()
        $py = $_.PerAxis.bY.ToString().ToLower()
        $pz = $_.PerAxis.bZ.ToString().ToLower()
        "(TargetBone=(BoneName=""$targetBone""),OffsetOption=$offset,TransformType=$ttype,PerAxis=(bX=$px,bY=$py,bZ=$pz))"
    }
    $weights = $node.ConstraintWeights | ForEach-Object { Format-Float $_ }

    $row  = $index % 10
    $col  = [math]::Floor($index / 10)
    $posX = $col * 400
    $posY = $row * 144

    $inLinkedTo  = if ($prevName) { ",LinkedTo=($prevName $prevOutGuid)" } else { "" }
    $outLinkedTo = if ($nextName) { ",LinkedTo=($nextName $nextInGuid)"  } else { "" }

    return @"
Begin Object Class=/Script/AnimGraph.AnimGraphNode_Constraint Name="$key"
   Node=(BoneToModify=(BoneName="$bone"),ConstraintSetup=({$($setupEntries -join ",")}),ConstraintWeights=({$($weights -join ",")}))
   ShowPinForProperties(0)=(PropertyName="ComponentPose",bShowPin=True)
   ShowPinForProperties(1)=(PropertyName="bAlphaBoolEnabled",bShowPin=True)
   ShowPinForProperties(2)=(PropertyName="Alpha",bShowPin=True)
   ShowPinForProperties(3)=(PropertyName="AlphaCurveName",bShowPin=True)
   NodePosX=$posX
   NodePosY=$posY
   CustomProperties Pin (PinId=$inGuid,PinName="ComponentPose",PinFriendlyName="Component Pose",PinType.PinCategory="struct",PinType.PinSubCategoryObject="/Script/Engine.ComponentSpacePoseLink"$inLinkedTo)
   CustomProperties Pin (PinId=$outGuid,PinName="Pose",Direction="EGPD_Output",PinType.PinCategory="struct",PinType.PinSubCategoryObject="/Script/Engine.ComponentSpacePoseLink"$outLinkedTo)
End Object
"@
}

# ---------------------------------------------------------------------------
# LayeredBoneBlend node formatter
# ---------------------------------------------------------------------------
function Format-LayeredBoneBlendNode {
    param ($key, $node, $index, $inGuid, $outGuid, $prevName, $prevOutGuid, $nextName, $nextInGuid)

    $layers = @()
    foreach ($layer in ($node.LayerSetup | Where-Object { $_ })) {
        $filters = @()
        foreach ($f in ($layer.BranchFilters | Where-Object { $_ })) {
            $filters += '(BoneName="{0}",BlendDepth={1})' -f $f.BoneName, [int]$f.BlendDepth
        }
        $layers += "(BranchFilters=({0}))" -f ($filters -join ",")
    }
    $layerSetup     = "LayerSetup=({0})" -f ($layers -join ",")
    $meshSpaceRot   = $node.bMeshSpaceRotationBlend.ToString()
    $meshSpaceScale = $node.bMeshSpaceScaleBlend.ToString()
    $curveBlend     = ($node.CurveBlendOption -split "::")[-1]
    $blendRoot      = $node.bBlendRootMotionBasedOnRootBone.ToString()

    $weightsPart = ""
    if ($node.BlendWeights -and $node.BlendWeights.Count -gt 0) {
        $w = $node.BlendWeights | ForEach-Object { "{0:F6}" -f $_ }
        $weightsPart = ",BlendWeights=({0})" -f ($w -join ",")
    }

    $row  = $index % 10
    $col  = [math]::Floor($index / 10)
    $posX = $col * 400
    $posY = $row * 144

    $inLinkedTo  = if ($prevName) { ",LinkedTo=($prevName $prevOutGuid)" } else { "" }
    $outLinkedTo = if ($nextName) { ",LinkedTo=($nextName $nextInGuid)"  } else { "" }

    return @"
Begin Object Class=/Script/AnimGraph.AnimGraphNode_LayeredBoneBlend Name="$key"
   Node=($layerSetup,bMeshSpaceRotationBlend=$meshSpaceRot,bMeshSpaceScaleBlend=$meshSpaceScale,CurveBlendOption=$curveBlend,bBlendRootMotionBasedOnRootBone=$blendRoot$weightsPart)
   NodePosX=$posX
   NodePosY=$posY
   CustomProperties Pin (PinId=$inGuid,PinName="ComponentPose",PinFriendlyName="Component Pose",PinType.PinCategory="struct",PinType.PinSubCategoryObject="/Script/Engine.ComponentSpacePoseLink"$inLinkedTo)
   CustomProperties Pin (PinId=$outGuid,PinName="Pose",Direction="EGPD_Output",PinType.PinCategory="struct",PinType.PinSubCategoryObject="/Script/Engine.ComponentSpacePoseLink"$outLinkedTo)
End Object
"@
}

# ---------------------------------------------------------------------------
# First pass — collect all nodes and pre-generate GUIDs
# ---------------------------------------------------------------------------
$nodeList = @()

foreach ($key in $props.PSObject.Properties.Name) {
    $node = $props.$key
    $type = $null

    if      ($key -like "AnimGraphNode_KawaiiPhysics*")   { $type = "Kawaii" }
    elseif  ($key -like "AnimGraphNode_ModifyBone*")       { $type = "ModifyBone" }
    elseif  ($key -like "AnimGraphNode_Constraint*")       { $type = "Constraint" }
    elseif  ($key -like "AnimGraphNode_LayeredBoneBlend*") { $type = "LayeredBoneBlend" }

    if ($type) {
        $nodeList += [PSCustomObject]@{
            Key     = $key
            Node    = $node
            Type    = $type
            InGuid  = New-Guid
            OutGuid = New-Guid
        }
    }
}

Write-Host "Total nodes to process: $($nodeList.Count)"

# ---------------------------------------------------------------------------
# Second pass — format each node with prev/next link info
# ---------------------------------------------------------------------------
for ($i = 0; $i -lt $nodeList.Count; $i++) {
    $entry = $nodeList[$i]
    $prev  = if ($i -gt 0)                    { $nodeList[$i - 1] } else { $null }
    $next  = if ($i -lt $nodeList.Count - 1)  { $nodeList[$i + 1] } else { $null }

    $prevName   = if ($prev) { $prev.Key }    else { $null }
    $prevOutGuid = if ($prev) { $prev.OutGuid } else { $null }
    $nextName   = if ($next) { $next.Key }    else { $null }
    $nextInGuid  = if ($next) { $next.InGuid }  else { $null }

    Write-Host "Processing $($entry.Type): $($entry.Key)"

    switch ($entry.Type) {
        "Kawaii"          { $output += Format-KawaiiPhysicsNode   $entry.Key $entry.Node $i $entry.InGuid $entry.OutGuid $prevName $prevOutGuid $nextName $nextInGuid }
        "ModifyBone"      { $output += Format-ModifyBoneNode       $entry.Key $entry.Node $i $entry.InGuid $entry.OutGuid $prevName $prevOutGuid $nextName $nextInGuid }
        "Constraint"      { $output += Format-ConstraintNode       $entry.Key $entry.Node $i $entry.InGuid $entry.OutGuid $prevName $prevOutGuid $nextName $nextInGuid }
        "LayeredBoneBlend"{ $output += Format-LayeredBoneBlendNode $entry.Key $entry.Node $i $entry.InGuid $entry.OutGuid $prevName $prevOutGuid $nextName $nextInGuid }
    }
}

if ($output.Count -eq 0) {
    Write-Host "No recognised AnimGraph nodes found."
    exit 1
}

$output -join "`n" | Out-File -Encoding utf8 -FilePath $OutputTxtPath
Set-Clipboard -Value ($output -join "`n")
Write-Host "`nDone. $($output.Count) node(s) written to $OutputTxtPath and copied to clipboard."