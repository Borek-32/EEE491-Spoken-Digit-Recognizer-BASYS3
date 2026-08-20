# Notices and provenance

## License scope

The MIT License applies to the original RTL, testbenches, scripts, MATLAB code,
KiCad design sources, constraint files, and project documentation authored for
this project.

The final report, photographs, rendered figures, and retained implementation or
test evidence are provided as portfolio and verification material. Copyright
remains with Kerem Gürbüz; their inclusion does not grant a separate broad
media-reuse license. Third-party trademarks and quoted or reproduced material
remain the property of their respective owners.

## AMD/Xilinx IP

Files under `ip/` and `hardware/pcb_adc_uart/ip/` are configuration metadata
for AMD/Xilinx LogiCORE IP. No generated IP HDL, encrypted simulation models,
checkpoints, or bitstreams are distributed. Recreating the design requires a
compatible licensed Vivado installation and is subject to AMD's applicable
license terms. AMD, Xilinx, Vivado, LogiCORE and XFFT are trademarks of their
respective owners. This project is not endorsed by AMD.

The numeric XFFT comparison file under `verification/tb_output/` is retained as
test evidence produced by the AMD bit-accurate model; it is not an implementation
of that model.

## Hardware references

Basys 3 and Digilent are trademarks of Digilent. The ADC interface is based on
the Texas Instruments ADC121S101 datasheet. Datasheets are linked, not copied.
The KiCad project contains standard-library footprint and symbol identifiers;
KiCad itself is not bundled.

## Curated-release transformations

The public release was assembled from the finalized local project without
modifying the original dirty worktree. The following non-electrical privacy and
portability transformations were made in this release copy:

- machine-specific absolute paths in retained text reports and KiCad evidence
  were replaced with relative paths or `<isolated-build>`;
- JTAG serials and stable UART device identifiers were removed from reusable
  scripts and documentation; callers must provide explicit live targets;
- the visible decorative `borek32` copper marking was retained as intentional
  public attribution; it is not a machine-path or device-identity leak;
- vendor-authored XCI files were retained byte-for-byte and are staged under a
  compatible external layout so their relative initialization paths resolve;
- generated projects, IP products, logs, checkpoints, waveform databases,
  bitstreams, PID files, backup documents, and the editable report source were
  excluded.

Historical measurements and limitations were not upgraded by these editorial
changes. See `README.md`, `REPRODUCIBILITY.md`, and the local evidence READMEs
for the preserved verification boundary.
