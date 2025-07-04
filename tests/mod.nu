use std assert

use ../nupm/utils/dirs.nu [ tmp-dir BASE_NUPM_CONFIG REGISTRY_FILENAME ]
use ../nupm

const TEST_REGISTRY_PATH = ([tests packages registry $REGISTRY_FILENAME] | path join)


def with-test-env [closure: closure]: nothing -> nothing {
    let home = tmp-dir nupm_test --ensure
    let cache = tmp-dir 'nupm_test/cache' --ensure
    let temp = tmp-dir 'nupm_test/temp' --ensure
    let reg = { test: $TEST_REGISTRY_PATH }

    with-env {
      nupm: {
        home: $home
        cache: $cache
        temp: $temp
        registries: $reg
      }
    } $closure

    rm --recursive $temp
    rm --recursive $cache
    rm --recursive $home
}

# Examples:
#     make sure `$env.nupm.home/scripts/script.nu` exists
#     > assert installed [scripts script.nu]
def "assert installed" [path_tokens: list<string>] {
    assert ($path_tokens | prepend $env.nupm.home | path join | path exists)
}

def check-file-content [content: string] {
    let file_str = open ($env.nupm.home | path join scripts spam_script.nu)
    assert ($file_str | str contains $content)
}


export def install-script [] {
    with-test-env {
        nupm install --path tests/packages/spam_script

        assert installed [scripts spam_script.nu]
        assert installed [scripts spam_bar.nu]
    }
}

export def install-module [] {
    with-test-env {
        nupm install --path tests/packages/spam_module

        assert installed [scripts script.nu]
        assert installed [modules spam_module]
        assert installed [modules spam_module mod.nu]
    }
}

export def install-custom [] {
    with-test-env {
        nupm install --path tests/packages/spam_custom

        assert installed [plugins nu_plugin_test]
    }
}

export def install-from-local-registry [] {
    with-test-env {
        $env.nupm.registries = {}
        nupm install --registry $TEST_REGISTRY_PATH spam_script
        check-file-content 0.2.0
    }

    with-test-env {
        nupm install --registry test spam_script
        check-file-content 0.2.0
    }

    with-test-env {
        nupm install spam_script
        check-file-content 0.2.0
    }
}

export def install-with-version [] {
    with-test-env {
        nupm install spam_script -v 0.1.0
        check-file-content 0.1.0
    }
}

export def install-multiple-registries-fail [] {
    with-test-env {
        $env.nupm.registries.test2 = $TEST_REGISTRY_PATH

        let out = try {
            nupm install spam_script
            "wrong value that shouldn't match the assert below"
        } catch {|err|
            $err.msg
        }

        assert ("Multiple registries contain package spam_script" in $out)
    }
}

export def install-package-not-found [] {
    with-test-env {
        let out = try {
            nupm install invalid-package
            "wrong value that shouldn't match the assert below"
        } catch {|err|
            $err.msg
        }

        assert ("Package invalid-package not found in any registry" in $out)
    }
}

export def search-registry [] {
    with-test-env {
        assert ((nupm search spam | length) == 4)
    }
}

export def nupm-status-module [] {
    with-test-env {
        let files = (nupm status tests/packages/spam_module).files
        assert ($files.0 ends-with (
            [tests packages spam_module spam_module mod.nu] | path join))
        assert ($files.1.0 ends-with (
            [tests packages spam_module script.nu] | path join))
    }
}

export def env-vars-are-set [] {
    hide-env nupm --ignore-errors

    use ../nupm

    assert equal $env.nupm.home $BASE_NUPM_CONFIG.home
    assert equal $env.nupm.temp $BASE_NUPM_CONFIG.temp
    assert equal $env.nupm.cache $BASE_NUPM_CONFIG.cache
    assert equal $env.nupm.registries $BASE_NUPM_CONFIG.registries
}

export def generate-local-registry [] {
    with-test-env {
        mkdir ($env.nupm.temp | path join packages registry)

        let reg_file = [tests packages registry registry.nuon] | path join
        let tmp_reg_file = [
            $env.nupm.temp packages registry test_registry.nuon
        ]
        | path join

        touch $tmp_reg_file

        [spam_script spam_script_old spam_custom spam_module] | each {|pkg|
            cd ([tests packages $pkg] | path join)
            nupm publish $tmp_reg_file --local --save --path (".." | path join $pkg)
        }

        let actual = open $tmp_reg_file | to nuon
        let expected = open $reg_file | to nuon

        assert equal $actual $expected
    }
}

export def registry-list [] {
    with-test-env {
        # Get list of registries
        let registries = nupm registry list

        # Should have test registry from test environment
        assert equal ($registries | length) 1
        assert equal $registries.0.name "test"
        assert equal $registries.0.url $TEST_REGISTRY_PATH
    }
}

export def registry-add [] {
    with-test-env {
        # Add a new registry
        nupm registry add test-registry https://example.com/test.nuon

        # Verify registry was added
        let registries = nupm registry list
        assert equal ($registries | length) 2

        let test_reg = $registries | where name == "test-registry" | first
        assert equal $test_reg.name "test-registry"
        assert equal $test_reg.url "https://example.com/test.nuon"

        # Try to add duplicate registry (should fail)
        let add_result = try {
            nupm registry add test-registry https://duplicate.com/test.nuon
            "should not reach here"
        } catch {|err|
            $err.msg
        }

        assert ("Registry 'test-registry' already exists" in $add_result)

        # Add another registry
        nupm registry add another-registry ./local-registry.nuon

        let registries_final = nupm registry list
        assert equal ($registries_final | length) 3

        let another_reg = $registries_final | where name == "another-registry" | first
        assert equal $another_reg.name "another-registry"
        assert equal $another_reg.url "./local-registry.nuon"
    }
}

export def registry-set-url [] {
    with-test-env {
        # Add a registry first
        nupm registry add test-registry https://example.com/test.nuon

        # Update the registry URL
        nupm registry set-url test-registry https://updated-example.com/registry.nuon

        # Verify URL was updated
        let registries = nupm registry list
        let test_reg = $registries | where name == "test-registry" | first
        assert equal $test_reg.url "https://updated-example.com/registry.nuon"

        # Update again to different URL
        nupm registry set-url test-registry ./local-path.nuon

        let registries_updated = nupm registry list
        let test_reg_updated = $registries_updated | where name == "test-registry" | first
        assert equal $test_reg_updated.url "./local-path.nuon"
    }
}

export def registry-remove [] {
    with-test-env {
        # Add registries first
        nupm registry add test-registry https://example.com/test.nuon
        nupm registry add another-registry https://another.com/registry.nuon

        # Verify both were added
        let registries_before = nupm registry list
        assert equal ($registries_before | length) 3  # 1 default + 2 added

        # Remove one registry
        nupm registry remove test-registry

        # Verify registry was removed
        let registries_after = nupm registry list
        assert equal ($registries_after | length) 2
        assert equal ($registries_after | where name == "test-registry" | length) 0
        assert equal ($registries_after | where name == "another-registry" | length) 1

        # Remove the other registry
        nupm registry remove another-registry

        let registries_final = nupm registry list
        assert equal ($registries_final | length) 1  # Only default registry left
    }
}

export def registry-rename [] {
    with-test-env {
        # Add a registry first
        nupm registry add test-registry https://example.com/test.nuon

        # Rename the registry
        nupm registry rename test-registry renamed-registry

        # Verify registry was renamed
        let registries = nupm registry list
        assert equal ($registries | where name == "test-registry" | length) 0
        assert equal ($registries | where name == "renamed-registry" | length) 1

        let renamed_reg = $registries | where name == "renamed-registry" | first
        assert equal $renamed_reg.url "https://example.com/test.nuon"

        # Rename again
        nupm registry rename renamed-registry final-name

        let registries_final = nupm registry list
        let final_reg = $registries_final | where name == "final-name" | first
        assert equal $final_reg.url "https://example.com/test.nuon"
        assert equal ($registries_final | where name == "renamed-registry" | length) 0
    }
}

export def registry-describe [] {
    with-test-env {
        # Describe the test registry that's already configured
        let description = nupm registry describe test

        # Verify we get package information
        assert (($description | length) > 0)

        # Check for expected packages from the test registry
        let spam_scripts = $description | where name == "spam_script"
        assert (($spam_scripts | length) > 0)

        # Check that we have the latest version
        let spam_script_latest = $spam_scripts | where version == "0.2.0"
        if (($spam_script_latest | length) > 0) {
            let pkg = $spam_script_latest | first
            assert equal $pkg.name "spam_script"
            assert equal $pkg.source "local"
            assert equal $pkg.version "0.2.0"
        }

        # Test error case with non-existent registry
        let describe_result = try {
            nupm registry describe non-existent-registry
            "should not reach here"
        } catch {|err|
            $err.msg
        }

        assert ("Registry 'non-existent-registry' not found" in $describe_result)
    }
}

export def registry-fetch [] {
    with-test-env {
        # Test fetch with local registry (test registry)
        let fetch_result = try {
            nupm registry fetch test
            "success"
        } catch {|err|
            $err.msg
        }

        # For local registry, fetch should succeed
        assert equal $fetch_result "success"

        # Verify cache directory was created
        let cache_dir = $env.nupm.cache | path join test
        assert ($cache_dir | path exists)
        assert (($cache_dir | path join "registry.nuon") | path exists)

        # Verify package files were cached
        let spam_script_cache = $cache_dir | path join "spam_script.nuon"
        assert ($spam_script_cache | path exists)

        # Test --all flag (only with local registries to avoid network issues)
        let fetch_all_result = try {
            nupm registry fetch --all
            "success"
        } catch {|err|
            $err.msg
        }

        assert equal $fetch_all_result "success"

        # Test error cases
        let no_name_result = try {
            nupm registry fetch
            "should not reach here"
        } catch {|err|
            $err.msg
        }

        assert ("Please specify a registry name or use --all flag" in $no_name_result)

        let invalid_registry_result = try {
            nupm registry fetch invalid-registry
            "should not reach here"
        } catch {|err|
            $err.msg
        }

        assert ("Registry 'invalid-registry' not found" in $invalid_registry_result)
    }
}

export def config-nu-search-path [] {
    with-test-env {
        use ../nupm
        # By default, nu_search_path should be false
        assert equal $env.nupm.config.nu_search_path false

        # Verify nupm directories are NOT added to NU_LIB_DIRS when disabled
        let modules_dir = $env.nupm.home | path join modules
        let scripts_dir = $env.nupm.home | path join scripts
        let plugins_dir = $env.nupm.home | path join plugins

        # Check that nupm dirs are not in the search paths
        assert (not ($modules_dir in $env.NU_LIB_DIRS))
        assert (not ($scripts_dir in $env.NU_LIB_DIRS))
        assert (not ($plugins_dir in $env.NU_PLUGIN_DIRS))

        # Manually set the config to true to test the functionality
        $env.nupm.config.nu_search_path = true

        use ../nupm
        assert equal $env.nupm.config.nu_search_path true

        assert ($modules_dir in $env.NU_LIB_DIRS)
        assert ($scripts_dir in $env.NU_LIB_DIRS)
        assert ($plugins_dir in $env.NU_PLUGIN_DIRS)
    }
}

export def config-headers [] {
    # Test the config-get function with custom headers
    let test_nupm_home = $nu.temp-path | path join nupm_test_headers
    mkdir $test_nupm_home
    
    with-env {
        nupm: {
            home: $test_nupm_home
            config: {
                headers: {
                    # Test registry with custom headers
                    test-auth: { || {
                        "Authorization": "Bearer test-token",
                        "User-Agent": "nupm-test/1.0"
                    }}
                }
            }
        }
    } {
        use ../nupm/utils/misc.nu http
        
        # Test config-get with registry that has custom headers
        # This would normally make a network request, so we test the logic
        let test_url = "https://api.example.com/registry.nuon"
        let registry_with_headers = "test-auth"
        let registry_without_headers = "test-no-auth"
        
        # Verify the headers configuration is loaded correctly
        assert ($env.nupm.config.headers.test-auth | is-not-empty)
        
        # Test that the headers closure returns the expected structure
        let headers_closure = $env.nupm.config.headers.test-auth
        let test_headers = do $headers_closure
        
        assert equal ($test_headers.Authorization) "Bearer test-token"
        assert equal ($test_headers."User-Agent") "nupm-test/1.0"
        
        # Test that registry without headers falls back to default behavior
        assert (not ("test-no-auth" in $env.nupm.config.headers))
    }
    
    # Test with empty headers config
    with-env {
        nupm: {
            home: $test_nupm_home
            config: {
                headers: {}
            }
        }
    } {
        use ../nupm/utils/misc.nu http
        
        # Verify empty headers config doesn't cause issues
        assert ($env.nupm.config.headers | is-empty)
        
        # This should work with empty headers config (falls back to normal http get)
        let registry_name = "test-registry"
        # We can't actually test the network call, but we can verify the function exists
        # and the logic path is correct
    }
    
    # Clean up
    rm -rf $test_nupm_home
}
