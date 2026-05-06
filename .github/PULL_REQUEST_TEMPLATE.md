## Summary

<!-- Short summary of what this PR does (e.g. "Add Minecraft Fabric template", "Fix port mapping for Valheim"). -->

## Template details

- Game name: <!-- e.g. "Minecraft" -->
- Template file path: <!-- e.g. "templates/minecraft/fabric.yaml" -->
- Template description (`description` field): <!-- copy from YAML -->
- Docker image: <!-- e.g. "itzg/minecraft-server:latest" -->

## Checklist

<!-- Please confirm the following before requesting review. -->

- [ ] The template file is placed at `templates/{game-name}/{template-description}.yaml`.
- [ ] The template passes schema validation (`template.schema.json`) locally or in CI.
- [ ] `name`, `description`, `game_id`, `docker_image_name`, and `docker_image_tag` are set.
- [ ] All ports in `port_mapping` are valid (1–65535) and documented if non-standard.
- [ ] Environment variables are documented or obvious (e.g. `version`, `MEMORY`, etc.).
- [ ] `file_downloads` URLs are reachable and use versions/placeholders correctly.

## Testing

<!-- Describe how you tested this template. For example: -->

- [ ] Template was deployed on a test server.
- Steps:
  1. <!-- e.g. "Created a server from this template with version 1.20.4" -->
  2. <!-- e.g. "Verified server started and players could join" -->

## Additional context

<!-- Anything else reviewers should know (breaking changes, dependencies, notes for operators, etc.). -->

