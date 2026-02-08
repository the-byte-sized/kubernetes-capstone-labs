# Using Git Checkpoints

This repository uses **commit-based checkpoints** to mark the start and end of each day's lab.

---

## 🏷️ Checkpoint Structure

Each day has two logical checkpoints:

1. **`day-X-start`** = Beginning of the day (previous day complete, or empty for Day 1)
2. **`day-X-end`** = End of the day (all manifests for Day X working)

---

## 📍 Day 1 Checkpoints

### Day 1 Start
**Commit:** `4fde9b16c7bd005fa064fe4d92978c91facd2404`  
**What's included:** Root README, LICENSE, .gitignore (no Day 1 manifests yet)

```bash
# Checkout Day 1 starting point
git checkout 4fde9b16c7bd005fa064fe4d92978c91facd2404

# Or create a local branch
git checkout -b day-1-start 4fde9b16c7bd005fa064fe4d92978c91facd2404
```

### Day 1 End
**Commit:** `4df238e1addd7f455a1ddbc7c9d63120493c2010` (latest)
**What's included:** Complete Day 1 (ConfigMap, Pod, verify.sh, troubleshooting)

```bash
# Checkout Day 1 complete
git checkout 4df238e1addd7f455a1ddbc7c9d63120493c2010

# Or return to main branch
git checkout main
```

---

## 🚀 Common Workflows

### Scenario 1: Following the Course Linearly

**Default workflow (recommended for most students):**

```bash
# Clone repository
git clone https://github.com/the-byte-sized/kubernetes-capstone-labs.git
cd kubernetes-capstone-labs

# You're on 'main' branch by default (latest state)

# Start with Day 1
cd day-1-foundation/
cat README.md
kubectl apply -f manifests/
./verify.sh

# Move to Day 2 when ready
cd ../day-2-replication/
# ... and so on
```

---

### Scenario 2: Missed a Day, Need to Catch Up

**Example: You missed Day 1, joining on Day 2**

```bash
# Clone repository
git clone https://github.com/the-byte-sized/kubernetes-capstone-labs.git
cd kubernetes-capstone-labs

# Checkout Day 2 starting point (= Day 1 end)
git checkout <day-2-start-commit>

# Day 1 is now complete in the repo
# Apply Day 1 manifests to your cluster
kubectl apply -f day-1-foundation/manifests/

# Verify Day 1 works
cd day-1-foundation/
./verify.sh

# Now start Day 2
cd ../day-2-replication/
cat README.md
```

---

### Scenario 3: Want to See Solution After Trying

**You've been working on Day 2, want to compare with official solution:**

```bash
# Save your work first
git stash  # Or commit to a local branch

# Checkout Day 2 complete solution
git checkout <day-2-end-commit>

# View solution files
cat day-2-replication/manifests/02-deployment-web.yaml

# Compare with your attempt
git diff stash@{0} -- day-2-replication/manifests/

# Return to your work
git checkout main
git stash pop
```

---

### Scenario 4: Start Fresh from a Specific Day

**Clean slate for Day 3:**

```bash
# Delete cluster resources
kubectl delete all --all

# Checkout Day 3 starting point
git checkout <day-3-start-commit>

# Apply previous days (Day 1 + 2)
kubectl apply -f day-1-foundation/manifests/
kubectl apply -f day-2-replication/manifests/

# Verify
kubectl get all

# Now work on Day 3
cd day-3-multitier/
```

---

## 📝 Checkpoint Reference Table

| Checkpoint | Commit SHA | What's Included | Use Case |
|------------|-----------|-----------------|----------|
| **Initial** | `5dab2ac1` | Empty repo (GitHub init) | Rarely needed |
| **day-1-start** | `4fde9b16` | Root README only | Starting from scratch |
| **day-1-end** | `4df238e1` | Day 1 complete | Move to Day 2 / catch up |
| **day-2-start** | TBD | Day 1 complete | Starting Day 2 |
| **day-2-end** | TBD | Day 1 + 2 complete | Move to Day 3 / catch up |
| **day-3-start** | TBD | Day 1 + 2 complete | Starting Day 3 |
| **day-3-end** | TBD | Day 1 + 2 + 3 complete | Move to Day 4 / review |

**Note:** Commit SHAs will be updated as new days are added.

---

## 🤔 Why Commits Instead of Git Tags?

This approach uses **commit SHAs** directly instead of Git tags for simplicity during development. 

Once the course stabilizes, we may add formal Git tags like `v1.0-day-1-end`.

**For now:** Bookmark this page and use the commit SHAs above.

---

## ❓ FAQ

### Q: Can I modify files and still follow checkpoints?

**A:** Yes, but commit your changes to a local branch first:

```bash
# Save your work
git checkout -b my-solutions
git add .
git commit -m "My Day 1 solution"

# Now you can switch to checkpoints
git checkout <day-2-start-commit>

# Return to your work
git checkout my-solutions
```

### Q: What if I break something and want to reset?

**A:**

```bash
# Discard all local changes (WARNING: destructive)
git reset --hard <commit-sha>

# Or just reset a specific folder
git checkout <commit-sha> -- day-1-foundation/
```

### Q: How do I see what changed between checkpoints?

**A:**

```bash
# Show files changed between Day 1 start and end
git diff 4fde9b16..4df238e1 --name-only

# Show full diff
git diff 4fde9b16..4df238e1

# Show diff for specific file
git diff 4fde9b16..4df238e1 -- day-1-foundation/manifests/02-pod-web.yaml
```

---

## 📚 Further Reading

- [Git Basics - Tagging](https://git-scm.com/book/en/v2/Git-Basics-Tagging)
- [Git Checkout Documentation](https://git-scm.com/docs/git-checkout)
- [Working with Branches](https://git-scm.com/book/en/v2/Git-Branching-Basic-Branching-and-Merging)

---

**Questions?** Open an [issue](https://github.com/the-byte-sized/kubernetes-capstone-labs/issues) with the `documentation` label.
