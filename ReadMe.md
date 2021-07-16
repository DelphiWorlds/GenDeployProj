# GenDeployProj

## Description

A command line tool for generating a `.deployproj` file from a `.dproj` in [Delphi](https://www.embarcadero.com/products/delphi) projects

**NOTE** This tool was "thrown together" and has had very little testing, so please bear that in mind. The code has been made available due to some interest in automating generation of `.deployproj` files without needing to use the Delphi IDE.

## Usage 

`gendeployproj <DprojFileName> [0|1]`

e.g.: `gendeployproj C:\Projects\MyProject\MyProject.dproj 1`

`<DprojFileName>` is the .dproj file for the project
`[0|1]` is an optional flag to indicate whether or not to overwrite the .deployproj if it exists. 0 (do not overwrite) is the default. If the `.deployproj` exists and 0 is specified, gendeployproj does nothing and returns an exit code of `0`

The .deployproj file is created in the same folder as the .dproj

## Exit codes

0 - Success. Note that this code is returned if the overwrite option is `0` and the `.deployproj` file exists

1 - `.dproj` file does not exist

2 - Could not read the `.dproj` file

3 - Could not find the `ProjectExtensions` or `Deployment` node in the `.dproj` (probably not a valid `.dproj`)

4 - Could not write the `.deployproj` file

