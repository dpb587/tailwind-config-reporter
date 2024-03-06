package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/google/go-github/v59/github"
)

var reConfigFileName = regexp.MustCompile(`^tailwind\.config\.(js|cjs|mjs|ts)$`)
var rePathMeta = regexp.MustCompile(`(?i)(^|[^a-z0-9])(examples?|fixtures?|samples?|stubs?|tests?)([^a-z0-9]|$)`)

var ctx = context.Background()
var client = github.NewClient(nil).WithAuthToken(os.Getenv("GITHUB_API_TOKEN"))
var stateFile = "../mnt/dataset/seed/github.jsonl"
var stateCacheDuration = 36 * time.Hour

var staleRepositoryTime = time.Now().Add(-1 * 1.8 * 365 * 24 * time.Hour)

type stateData []stateRepositoryData

func (s *stateData) GetRepository(name string) (stateRepositoryData, bool) {
	for _, v := range *s {
		if v.Name == name {
			return v, true
		}
	}

	return stateRepositoryData{}, false
}

func (s *stateData) PutRepository(d stateRepositoryData) {
	fmt.Fprintf(os.Stderr, "%#+v\n", d)

	for vIdx, v := range *s {
		if v.Name == d.Name {
			(*s)[vIdx] = d

			return
		}
	}

	*s = append(*s, d)
}

func (s *stateData) ReadFile(name string) error {
	buf, err := os.ReadFile(name)
	if err != nil {
		return fmt.Errorf("read: %w", err)
	}

	ns := stateData{}

	d := json.NewDecoder(bytes.NewReader(buf))

	for d.More() {
		var dr stateRepositoryData

		err := d.Decode(&dr)
		if err != nil {
			return fmt.Errorf("decode: %v", err)
		}

		ns = append(ns, dr)
	}

	*s = ns

	return nil
}

func (s *stateData) WriteFile(name string) error {
	sort.Slice(*s, func(i, j int) bool {
		return strings.Compare((*s)[i].Name, (*s)[j].Name) < 0
	})

	buf := bytes.NewBuffer(nil)

	e := json.NewEncoder(buf)

	for _, v := range *s {
		err := e.Encode(v)
		if err != nil {
			return fmt.Errorf("encode: %v", err)
		}
	}

	err := os.WriteFile(name, buf.Bytes(), 0600)
	if err != nil {
		return fmt.Errorf("write: %v", err)
	}

	return nil
}

type stateRepositoryData struct {
	Name        string
	Valid       bool
	CachedAt    time.Time
	CachedData  stateRepositoryCacheData
	FileMatches []stateRepositoryFileMatchData
}

type stateRepositoryCacheData struct {
	Fork              bool
	Archived          bool
	DefaultBranchName *string
	UpdatedAt         time.Time
	StargazersCount   int
	LastCommitAt      *time.Time
}

type stateRepositoryFileMatchData struct {
	Path       string
	Valid      bool
	CachedAt   time.Time
	CachedData stateRepositoryFileMatchCacheData
}

type stateRepositoryFileMatchCacheData struct {
	ValidPackageFile     bool
	ValidTailwindPackage bool
}

func processRepository(state *stateData, owner, name string) error {
	repositoryName := fmt.Sprintf("github.com/%s/%s", owner, name)

	repositoryState, ok := state.GetRepository(repositoryName)
	if ok && repositoryState.CachedAt.After(time.Now().Add(-1*stateCacheDuration)) {
		return nil
	}

	time.Sleep(time.Second)

	repository, _, err := client.Repositories.Get(ctx, owner, name)
	if err != nil {
		return fmt.Errorf("get repository: %v", err)
	}

	repositoryState = stateRepositoryData{
		Name:     repositoryName,
		CachedAt: time.Now(),
		CachedData: stateRepositoryCacheData{
			Fork:              *repository.Fork,
			Archived:          *repository.Archived,
			DefaultBranchName: repository.DefaultBranch,
			UpdatedAt:         repository.UpdatedAt.Time,
			StargazersCount:   *repository.StargazersCount,
		},
	}

	if
	// skip empty repositories
	repositoryState.CachedData.DefaultBranchName == nil ||
		// avoid non-authoritative/canonical repositories
		repositoryState.CachedData.Fork ||
		// prefer more stable repositories than ad-hoc
		repositoryState.CachedData.StargazersCount < 5 ||
		// avoid repositories which are not well-maintained
		repositoryState.CachedData.Archived ||
		repositoryState.CachedData.UpdatedAt.Before(staleRepositoryTime) ||
		// prefer testing on concrete instances; skip for now
		rePathMeta.MatchString(repositoryState.Name) {
		state.PutRepository(repositoryState)

		return nil
	}

	repositoryCommit, _, err := client.Repositories.GetCommit(ctx, owner, name, fmt.Sprintf("heads/%s", *repository.DefaultBranch), nil)
	if err != nil {
		return fmt.Errorf("get commit: %v", err)
	}

	repositoryState.CachedData.LastCommitAt = &repositoryCommit.Commit.Committer.Date.Time

	// prefer testing on concrete instances; skip for now
	if repositoryState.CachedData.LastCommitAt.Before(staleRepositoryTime) {
		state.PutRepository(repositoryState)

		return nil
	}

	repositoryState.Valid = true

	repositoryCommitTree, _, err := client.Git.GetTree(ctx, owner, name, *repositoryCommit.Commit.Tree.SHA, true)
	if err != nil {
		return fmt.Errorf("get commit tree: %v", err)
	}

	for _, entry := range repositoryCommitTree.Entries {
		if *entry.Type != "blob" {
			continue
		} else if !reConfigFileName.MatchString(filepath.Base(*entry.Path)) {
			continue
		}

		repositoryState.FileMatches = append(repositoryState.FileMatches, stateRepositoryFileMatchData{
			Path:     *entry.Path,
			CachedAt: time.Now(),
		})

		fileMatchState := &repositoryState.FileMatches[len(repositoryState.FileMatches)-1]

		if
		// prefer testing on concrete instances; skip for now
		rePathMeta.MatchString(*entry.Path) ||
			// deeply-nested matches seem more utilitarian or example-focused; skip for now
			len(strings.Split(*entry.Path, "/")) > 3 {
			continue
		}

		dirPath := filepath.Dir(*entry.Path)
		if dirPath == "." {
			dirPath = ""
		}

		packageFile, _, _, err := client.Repositories.GetContents(
			ctx,
			owner,
			name,
			filepath.Join(dirPath, "package.json"),
			&github.RepositoryContentGetOptions{
				Ref: *repositoryCommit.SHA,
			},
		)
		if err != nil {
			if strings.Contains(err.Error(), "404 Not Found") {
				continue
			}

			return fmt.Errorf("get package.json: %v", err)
		} else if packageFile == nil {
			continue
		}

		fileMatchState.CachedData.ValidPackageFile = true

		packageFileContents, err := packageFile.GetContent()
		if err != nil {
			panic(err)
		}

		// not very strict, but avoid cases where file was forgotten
		// maybe need to include transitive/component packages?
		if !strings.Contains(packageFileContents, `tailwind`) {
			continue
		}

		fileMatchState.CachedData.ValidTailwindPackage = true

		fileMatchState.Valid = true
	}

	state.PutRepository(repositoryState)

	return nil
}

func main() {
	var state = &stateData{}

	if err := state.ReadFile(stateFile); err != nil {
		if !errors.Is(err, fs.ErrNotExist) {
			panic(err)
		}
	}

	if err := mainErr(state); err != nil {
		state.WriteFile(stateFile)

		panic(err)
	}
}

func mainErr(state *stateData) error {
	err := mainSearchRepositories(state, "tailwindcss in:topics")
	if err != nil {
		return fmt.Errorf("search code: %v", err)
	}

	err = mainSearchRepositories(state, "tailwind in:topics")
	if err != nil {
		return fmt.Errorf("search code: %v", err)
	}

	err = mainSearchCode(state)
	if err != nil {
		return fmt.Errorf("search code: %v", err)
	}

	return nil
}

func mainSearchRepositories(state *stateData, q string) error {
	opts := &github.SearchOptions{
		ListOptions: github.ListOptions{
			PerPage: 25,
		},
	}

	for {
		fmt.Fprintf(os.Stderr, "# INFO: SearchRepositories, page=%d\n", opts.ListOptions.Page)

		res, resp, err := client.Search.Repositories(ctx, q, opts)
		if err != nil {
			return fmt.Errorf("repository search: %v", err)
		}

		for _, repository := range res.Repositories {
			err := processRepository(state, *repository.Owner.Login, *repository.Name)
			if err != nil {
				return fmt.Errorf("repository (%s/%s): %v", *repository.Owner.Login, *repository.Name, err)
			}

			time.Sleep(1 * time.Second)
		}

		err = state.WriteFile(stateFile)
		if err != nil {
			return fmt.Errorf("write file: %v", err)
		}

		if resp.NextPage == 0 {
			break
		}

		time.Sleep(8 * time.Second)
		opts.Page = resp.NextPage
	}

	return nil
}

func mainSearchCode(state *stateData) error {
	opts := &github.SearchOptions{
		ListOptions: github.ListOptions{
			PerPage: 25,
		},
	}

	for {
		fmt.Fprintf(os.Stderr, "# INFO: SearchCode, page=%d\n", opts.ListOptions.Page)

		res, resp, err := client.Search.Code(ctx, "filename:tailwind.config", opts)
		if err != nil {
			return fmt.Errorf("code search: %v", err)
		}

		for _, codeResult := range res.CodeResults {
			err := processRepository(state, *codeResult.Repository.Owner.Login, *codeResult.Repository.Name)
			if err != nil {
				return fmt.Errorf("repository (%s/%s): %v", *codeResult.Repository.Owner.Login, *codeResult.Repository.Name, err)
			}

			time.Sleep(1 * time.Second)
		}

		err = state.WriteFile(stateFile)
		if err != nil {
			return fmt.Errorf("write file: %v", err)
		}

		if resp.NextPage == 0 {
			break
		}

		time.Sleep(8 * time.Second)
		opts.Page = resp.NextPage
	}

	return nil
}
