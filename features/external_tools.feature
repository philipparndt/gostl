@integration @external-tools
Feature: External Tool Integration
  As a user
  I want to integrate with external tools
  So that I can extend the application's capabilities

  Background:
    Given the application is running

  @go3mf
  Scenario: Open file with go3mf
    Given a file is loaded
    When I press O
    Then the go3mf CLI tool should be launched
    And the command should be "go3mf build <file> -o <output.3mf>"
    And GoSTL should open the built 3MF once the build succeeds

  @go3mf @recipe
  Scenario: Open a recipe with go3mf
    Given a go3mf YAML recipe is loaded
    When I press O
    Then the command should be "go3mf build <recipe>" with no -o
    And the 3MF that opens should be the one the recipe's output: names
      """
      Pressing O is an export somebody asked for, so it writes into the project
      - unlike showing a recipe, which must not. But go3mf takes the name from
      the recipe's output: and never from -o, so a recipe whose output: is not
      its own basename used to build correctly and then open a path that had
      never existed.
      """

  @go3mf
  Scenario: The built file is opened once and not twice
    Given a file is loaded
    When I press O
    Then the command should not contain "--open"
    And the built 3MF should be handed to the default application exactly once

  @go3mf
  Scenario: go3mf executable discovery
    When the application searches for go3mf
    Then it should check the following paths in order:
      | Path                      |
      | /usr/local/bin/go3mf      |
      | /opt/homebrew/bin/go3mf   |
      | ~/go/bin/go3mf            |
      | ~/.local/bin/go3mf        |
      | Shell PATH via 'which'    |

  @openscad
  Scenario: OpenSCAD executable discovery
    When the application searches for OpenSCAD
    Then it should check the following paths in order:
      | Path                                              |
      | /Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD |
      | /usr/local/bin/openscad                            |
      | /opt/homebrew/bin/openscad                         |
      | Shell PATH via 'which'                             |

  @openscad
  Scenario: Open file in OpenSCAD editor
    Given an OpenSCAD file is loaded
    When I press Cmd+E or select "Open in OpenSCAD" from Tools menu
    Then the .scad file should open in OpenSCAD.app
    And the user can edit the file in OpenSCAD
    And file watching should trigger a reload when the file is saved

  @openscad
  Scenario: Open in OpenSCAD disabled for non-SCAD files
    Given a non-OpenSCAD file is loaded (e.g., .stl or .3mf)
    Then the "Open in OpenSCAD" menu item should be disabled

  @openscad
  Scenario: OpenSCAD rendering
    Given an OpenSCAD file is loaded
    Then it should be rendered to a temporary STL file
    And the temporary file should be in /var/tmp/
    And the temporary file should be cleaned up after use

  @openscad
  Scenario: OpenSCAD dependency tracking
    Given an OpenSCAD file with include statements is loaded
    Then all included files should be tracked
    And changes to any included file should trigger a reload

  @openscad
  Scenario: OpenSCAD messages panel
    Given an OpenSCAD file is rendered
    When the OpenSCAD output contains warnings, deprecations, or echo statements
    Then a collapsible messages panel should appear in the bottom-right corner
    And the panel should show the message count
    And the panel should be expandable to show individual messages

  @openscad
  Scenario: OpenSCAD warning display
    Given an OpenSCAD file produces a warning like "WARNING: Can't open library"
    Then the warning should appear with an orange triangle icon
    And the "WARNING:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD deprecation display
    Given an OpenSCAD file produces a deprecation like "DEPRECATED: Variable names..."
    Then the deprecation should appear with a yellow clock icon
    And the "DEPRECATED:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD echo display
    Given an OpenSCAD file uses echo() statements like "ECHO: -53.6289"
    Then the echo output should appear with a cyan speech bubble icon
    And the "ECHO:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD error display
    Given an OpenSCAD file produces an error like "ERROR: Assertion failed"
    Then the error should appear with a red X circle icon
    And the "ERROR:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD trace display
    Given an OpenSCAD file produces a trace like "TRACE: called by 'align'"
    Then the trace should appear with a purple branch icon
    And the "TRACE:" prefix should be stripped from the display

  @openscad
  Scenario: Messages shown even on render failure
    Given an OpenSCAD file fails to render
    When the output contains ECHO, WARNING, ERROR, or TRACE messages
    Then the messages panel should still display all captured messages
    And this helps debug the issue that caused the render failure

  @openscad @2d
  Scenario: 2D OpenSCAD file rendering
    Given an OpenSCAD file containing only 2D geometry is loaded
    When the initial render fails with "Current top level object is not a 3D object"
    Then the file should be automatically re-rendered with linear_extrude
    And the 2D shapes should be extruded to 1mm height for visualization
    And the model should display successfully

  @openscad @2d
  Scenario: 2D OpenSCAD file with includes
    Given a 2D OpenSCAD file uses include or use statements
    When the file is rendered for 2D visualization
    Then the included dependencies should still be resolved
    And changes to included files should trigger reload
    And the 2D content from all files should be extruded together

  @openscad @colors
  Scenario: OpenSCAD color extraction
    Given an OpenSCAD file uses color() modules
    When the file is loaded
    Then colors should be automatically extracted using multi-pass rendering
    And each colored region should be rendered separately
    And triangles should be assigned their respective colors
    And the model should display with per-triangle colors

  @openscad @colors
  Scenario: Color extraction process
    Given an OpenSCAD file with multiple colors
    When GoSTL processes the file
    Then it should first convert the file to CSG format
    And extract unique colors by redefining color() to echo values
    And verify all geometry is wrapped in color() calls
    And render each color in parallel for efficiency
    And merge all colored triangles into a single model

  @openscad @colors
  Scenario: Fallback for uncolored geometry
    Given an OpenSCAD file has geometry not wrapped in color()
    When the file is loaded
    Then GoSTL should detect the uncolored geometry
    And fall back to standard (non-colored) rendering
    And the model should display using the selected material color

  @openscad @colors
  Scenario: Fallback for single color or white
    Given an OpenSCAD file uses only white or a single color
    When the file is loaded
    Then GoSTL should skip color extraction
    And use standard rendering for efficiency
    And the model should display using the selected material color

  @go3mf
  Scenario: go3mf YAML rendering
    Given a go3mf YAML configuration file is loaded
    Then it should be rendered to a temporary 3MF file via go3mf CLI
    And the command should be "go3mf build <recipe>" with no -o
    And go3mf should be run with a temporary directory as its working directory
    And the resulting 3MF should be parsed and displayed
    And the temporary build directory should be cleaned up on reload

  @go3mf @recipe
  Scenario: Showing a recipe does not write to the project it lives in
    Given a go3mf YAML recipe that declares "output: adapter-set.3mf"
    And a file of that name already exists beside the recipe
    When the recipe is loaded in the viewer
    Then the recipe's own directory should be byte for byte what it was
    And the built 3MF should be inside a temporary build directory
      """
      go3mf ignores -o for a recipe: a single YAML input takes CreatePlan down
      createYAMLPlan, the one plan that never receives the -o value, and the
      output name comes from the recipe's mandatory output: instead - written
      relative to go3mf's working directory, and then exit 0. Run in the
      recipe's own directory, as this did, that overwrote the project's .3mf
      under exactly the name the recipe names, which is where a hand-made or
      hand-sliced file normally sits, and then the viewer parsed a temporary
      file that had never been created.

      The working directory is the fix and is enough of one: go3mf resolves
      every file: against the recipe's own directory, so the parts are still
      found where they live. Nothing is copied and nothing is rewritten.
      """

  @go3mf @recipe
  Scenario: A recipe that names an output the viewer will not write
    Given a go3mf YAML recipe whose output: is an absolute path
    When the recipe is loaded in the viewer
    Then nothing should be built and nothing should be written
    And the error should name the output it refused
      """
      No working directory can contain an absolute path, so this is the one
      output: the viewer cannot keep out of the project. Refusing it and saying
      so is the honest answer; building it would overwrite a file somebody may
      have made by hand.
      """

  @go3mf @multi-plate
  Scenario: go3mf YAML with multiple plates
    Given a go3mf YAML configuration produces a multi-plate 3MF
    When the file is loaded
    Then the plate selector panel should appear
    And all plates from the generated 3MF should be available

  @go3mf @openscad @colors
  Scenario: Multi-color OpenSCAD export to go3mf
    Given an OpenSCAD file with multiple color() modules is loaded
    When I press O to open with go3mf
    Then GoSTL should export each color as a separate STL file
    And generate a go3mf YAML configuration with filament assignments
    And the generated configuration's output: should be the full destination path
    And each color gets assigned to a different filament (1, 2, 3, etc.)
    And go3mf should build a multi-color 3MF file
    And the 3MF file should open in the default application
      """
      The destination goes in the generated recipe rather than in -o, because for
      a recipe that is the only place go3mf reads it from. With the bare name
      there, go3mf wrote the result into the temporary export directory that the
      cleanup then deleted, and the file handed to the slicer had never existed.
      """

  @go3mf @openscad @colors
  Scenario: Single-color OpenSCAD export to go3mf
    Given an OpenSCAD file with no color() modules is loaded
    When I press O to open with go3mf
    Then GoSTL should export the model as a single STL file
    And pass it directly to go3mf (no YAML needed)
    And go3mf should build a standard 3MF file
