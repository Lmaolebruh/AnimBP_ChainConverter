# AnimBP_ChainConverter

## Quick start
Export desired assets from the game as JSON (with FModel).
Adjust paths in script(s) and run them.
CTRL+V inside Unreal to paste nodes.
Done.
## Documentation
## AnimBP Converter — AnimBP_Convert.ps1
### What it does
Reads an Animation Blueprint JSON.
Finds supported AnimGraph nodes and converts them to UE’s Copy/Paste format.
Auto-positions nodes and Auto links nodes and Automatically copies the output after parsing is done (also saves it to a txt file).
Currently supported nodes
KawaiiPhysics (Physics settings, curves, limits, Chains)
ModifyBone
Constraint
LayeredBoneBlend
Parameters
-InputJsonPath → Path to the exported input JSON (from FModel)
-OutputTxtPath → Where to save the UE paste text
-AnimBPClass → The AnimBlueprintGeneratedClass name (e.g., Post_1024303_Physics_C)
### Usage
Change the following params at the top of the scripts and then run the script. See above for parameter specifics.

param (
    [string]$InputJsonPath = "T:\Modding\Unreal Engine\_Scripts\Assets\Example.json",
    [string]$OutputTxtPath = "T:\Modding\Unreal Engine\_Scripts\AnimBP_Output.txt",
)
### Pasting into UE
Open your target Animation Blueprint.
Press CTRL+V — nodes appear with the same settings as the JSON.
The same text is also saved to the file specified in -OutputTxtPath.
