# Kistulentz Privacy

Kistulentz is local-first. It has no user accounts, advertising, analytics, telemetry, or third-party crash reporting.

## Data kept on the Mac

Kistulentz reads and writes only files the author chooses or creates through the app. Markdown documents, projects, project recovery snapshots, EPUB reference analysis, research-library indexes, attachments copied into a library, OCR results, revision history, and publication exports remain on the Mac in locations chosen by the author or inside the relevant project.

Declined-suggestion records and ordinary app settings are stored in local macOS preferences. OpenAI and Anthropic API keys are stored in the macOS Keychain. Kistulentz does not place API keys in projects, exported books, or reference libraries.

## Network requests

Kistulentz contacts an external service only after an author chooses one of these actions:

- An OpenAI or Anthropic writing action sends the material displayed in the confirmation preview to the chosen provider.
- An Ollama writing action sends that material to the author's local Ollama service at `localhost:11434`.
- A DOI lookup sends the entered DOI to Crossref.
- An ISBN lookup sends the entered ISBN to Open Library.

Automatic local analysis, local OCR, project migration and recovery, EPUB/reference imports, systemic revision scans, and publication exports do not contact an AI provider. Kistulentz does not automatically upload complete EPUB files, complete projects, or complete reference libraries.

Information sent to an external provider is handled under that provider's own terms and privacy policy. Authors should review the request preview and remove private or unnecessary material before confirming.

## Control and deletion

Authors control their Markdown, project, library, backup, and export files through Finder. Deleting those files removes that local data. API keys can be replaced or removed in Kistulentz Settings. Uninstalling the app does not delete author-created documents or libraries.

Privacy questions may be raised through the project's GitHub Issues page without attaching private writing, reference books, or API keys.
