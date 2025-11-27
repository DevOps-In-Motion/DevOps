
# Container CI/CD strategy


  1. Build image (with tests in Dockerfile)
  2. Run container-structure-tests
  3. Security scan (Trivy)
  4. Best practices check (Dockle)
  5. Spin up container + run integration tests
  6. Push to registry
  7. Tag as 'tested' or promote to production registry