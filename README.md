# AnimBP_ChainConverter

## Quick start
Export desired assets from the game as JSON (with FModel).
Adjust paths in script(s) and run them.
CTRL+V inside Unreal to paste nodes.
Done.
## Documentation
## AnimBP Converter — AnimBP_Convert.ps1
### What it does
- Reads an Animation Blueprint JSON.
- Finds supported AnimGraph nodes and converts them to UE’s Copy/Paste format.
- Auto-positions nodes and Auto links nodes and Automatically copies the output after parsing is done (also saves it to a txt file).
### Currently supported nodes
- KawaiiPhysics (Physics settings, curves, limits, Chains)
- ModifyBone
- Constraint
- LayeredBoneBlend
### Parameters
- InputJsonPath → Path to the exported input JSON (from FModel)
- OutputTxtPath → Where to save the UE paste text
### Usage
Right Click the file & "Run with Powershell"
- It will prompt you to give the OutputJsonPath (It saves it permanently for future use, you can reset this by changing it inside the code)
- And it will prompt you after to give it the InputJsonPath 

Make sure to remove quotations from the file paths
```.\AnimBP_Convert.ps1```
### Pasting into UE
Open your target Animation Blueprint.
Press CTRL+V — nodes appear with the same settings as the JSON.
The same text is also saved to the file specified in -OutputTxtPath.
