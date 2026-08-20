function digest = sha256_file(path)
%SHA256_FILE Return the lowercase SHA-256 digest of a local file.
%
% The digest is computed inside MATLAB so the live logger does not depend on
% a shell process while the MATLAB desktop owns the serial capture session.

path = string(path);
if ~isscalar(path) || ~isfile(path)
    error("MFCC:SHA256File", "File does not exist: %s", path);
end

[fid, message] = fopen(path, "rb");
if fid < 0
    error("MFCC:SHA256File", "Cannot open %s: %s", path, message);
end
cleanup = onCleanup(@() fclose(fid));

md = java.security.MessageDigest.getInstance("SHA-256");
while true
    [chunk, count] = fread(fid, 1024 * 1024, "*uint8");
    if count == 0
        break;
    end
    md.update(typecast(chunk(:), "int8"));
end

rawDigest = typecast(md.digest(), "uint8");
digest = lower(join(compose("%02x", rawDigest), ""));
end
