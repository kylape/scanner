package vulndump

import (
	"compress/flate"
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/mholt/archiver"
	"github.com/pkg/errors"
	"github.com/stackrox/scanner/database"
)

// WriteZip takes the given files and creates the vuln dump zip.
func WriteZip(inputDir, outFile string) error {
	zipArchive := archiver.NewZip()
	zipArchive.CompressionLevel = flate.BestCompression
	return zipArchive.Archive([]string{
		filepath.Join(inputDir, K8sDirName),
		filepath.Join(inputDir, ManifestFileName),
		filepath.Join(inputDir, NVDDirName),
		filepath.Join(inputDir, OSVulnsFileName),
	}, outFile)
}

func writeJSONObjectToFile(filePath string, object interface{}) error {
	f, err := os.Create(filePath)
	if err != nil {
		return errors.Wrap(err, "creating file")
	}
	if err := json.NewEncoder(f).Encode(object); err != nil {
		return errors.Wrap(err, "JSON-encoding into file")
	}
	return nil
}

// WriteManifestFile creates and writes the manifest file to the given output dir.
func WriteManifestFile(outputDir string, m Manifest) error {
	if err := writeJSONObjectToFile(filepath.Join(outputDir, ManifestFileName), m); err != nil {
		return errors.Wrap(err, "writing manifest file")
	}
	return nil
}

// WriteOSVulns creates and writes the OS vulns file to the given output dir.
func WriteOSVulns(outputDir string, vulns []database.Vulnerability) error {
	if err := writeJSONObjectToFile(filepath.Join(outputDir, OSVulnsFileName), vulns); err != nil {
		return errors.Wrap(err, "writing os vulns file")
	}
	return nil
}
