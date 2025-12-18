// DecisionAgent Rule Builder - Main Application
class RuleBuilder {
    constructor() {
        this.rules = [];
        this.currentRule = null;
        this.currentRuleIndex = null;
        this.currentCondition = null;
        this.init();
    }

    init() {
        this.bindEvents();
        this.updateJSONPreview();
    }

    bindEvents() {
        // Rule management
        document.getElementById('addRuleBtn').addEventListener('click', () => this.openRuleModal());
        document.getElementById('saveRuleBtn').addEventListener('click', () => this.saveRule());
        document.getElementById('closeModalBtn').addEventListener('click', () => this.closeModal());
        document.getElementById('cancelModalBtn').addEventListener('click', () => this.closeModal());

        // Actions
        document.getElementById('validateBtn').addEventListener('click', () => this.validateRules());
        document.getElementById('clearBtn').addEventListener('click', () => this.clearAll());
        document.getElementById('loadExampleBtn').addEventListener('click', () => this.loadExample());

        // Export/Import
        document.getElementById('copyBtn').addEventListener('click', () => this.copyJSON());
        document.getElementById('downloadBtn').addEventListener('click', () => this.downloadJSON());
        document.getElementById('importFile').addEventListener('change', (e) => this.importJSON(e));

        // Modal close on outside click
        document.getElementById('ruleModal').addEventListener('click', (e) => {
            if (e.target.id === 'ruleModal') {
                this.closeModal();
            }
        });

        // Operator change - hide/show value input
        document.addEventListener('change', (e) => {
            if (e.target.classList.contains('operator-select')) {
                this.handleOperatorChange(e.target);
            }
        });
    }

    openRuleModal(index = null) {
        this.currentRuleIndex = index;
        const modal = document.getElementById('ruleModal');
        const modalTitle = document.getElementById('modalTitle');

        if (index !== null) {
            // Edit existing rule
            this.currentRule = { ...this.rules[index] };
            modalTitle.textContent = `Edit Rule: ${this.currentRule.id}`;
            this.populateRuleModal(this.currentRule);
        } else {
            // New rule
            this.currentRule = {
                id: '',
                if: { field: '', op: 'eq', value: '' },
                then: { decision: '', weight: 0.8, reason: '' }
            };
            modalTitle.textContent = 'Create New Rule';
            this.populateRuleModal(this.currentRule);
        }

        modal.classList.remove('hidden');
    }

    populateRuleModal(rule) {
        document.getElementById('ruleId').value = rule.id || '';
        document.getElementById('thenDecision').value = rule.then?.decision || '';
        document.getElementById('thenWeight').value = rule.then?.weight || 0.8;
        document.getElementById('thenReason').value = rule.then?.reason || '';

        // Build condition UI
        const conditionBuilder = document.getElementById('conditionBuilder');
        conditionBuilder.innerHTML = '';

        if (!rule.if) {
            this.addFieldCondition(conditionBuilder);
        } else {
            this.buildConditionUI(rule.if, conditionBuilder);
        }
    }

    buildConditionUI(condition, container) {
        if (condition.field !== undefined) {
            // Field condition
            const conditionEl = this.createFieldCondition(condition);
            container.appendChild(conditionEl);
        } else if (condition.all !== undefined) {
            // All (AND) condition
            const compositeEl = this.createCompositeCondition('all', condition.all);
            container.appendChild(compositeEl);
        } else if (condition.any !== undefined) {
            // Any (OR) condition
            const compositeEl = this.createCompositeCondition('any', condition.any);
            container.appendChild(compositeEl);
        } else {
            // Fallback
            this.addFieldCondition(container);
        }
    }

    createFieldCondition(data = {}) {
        const template = document.getElementById('fieldConditionTemplate');
        const clone = template.content.cloneNode(true);
        const conditionItem = clone.querySelector('.condition-item');

        // Populate data
        if (data.field) conditionItem.querySelector('.field-path').value = data.field;
        if (data.op) conditionItem.querySelector('.operator-select').value = data.op;
        if (data.value !== undefined) conditionItem.querySelector('.field-value').value = data.value;

        // Handle operator-specific visibility
        const operatorSelect = conditionItem.querySelector('.operator-select');
        this.handleOperatorChange(operatorSelect);

        // Remove button
        conditionItem.querySelector('.btn-remove').addEventListener('click', (e) => {
            conditionItem.remove();
        });

        // Type change
        conditionItem.querySelector('.condition-type-select').addEventListener('change', (e) => {
            this.convertConditionType(conditionItem, e.target.value);
        });

        return conditionItem;
    }

    createCompositeCondition(type = 'all', subconditions = []) {
        const template = document.getElementById('compositeConditionTemplate');
        const clone = template.content.cloneNode(true);
        const conditionItem = clone.querySelector('.condition-item');
        const typeSelect = conditionItem.querySelector('.condition-type-select');
        const subContainer = conditionItem.querySelector('.subconditions-container');

        // Set type
        typeSelect.value = type;

        // Add subconditions
        if (subconditions.length === 0) {
            // Add one empty field condition
            subContainer.appendChild(this.createFieldCondition());
        } else {
            subconditions.forEach(subcond => {
                this.buildConditionUI(subcond, subContainer);
            });
        }

        // Add subcondition button
        conditionItem.querySelector('.btn-add-subcondition').addEventListener('click', () => {
            subContainer.appendChild(this.createFieldCondition());
        });

        // Remove button
        conditionItem.querySelector('.btn-remove').addEventListener('click', () => {
            conditionItem.remove();
        });

        // Type change
        typeSelect.addEventListener('change', (e) => {
            this.convertConditionType(conditionItem, e.target.value);
        });

        return conditionItem;
    }

    convertConditionType(conditionItem, newType) {
        const parent = conditionItem.parentElement;
        if (!parent) return;

        if (newType === 'field') {
            // Convert to field condition
            const newCondition = this.createFieldCondition();
            parent.replaceChild(newCondition, conditionItem);
        } else {
            // Convert to composite (all/any)
            const newCondition = this.createCompositeCondition(newType);
            parent.replaceChild(newCondition, conditionItem);
        }
    }

    addFieldCondition(container) {
        const conditionEl = this.createFieldCondition();
        container.appendChild(conditionEl);
    }

    handleOperatorChange(selectElement) {
        const valueInput = selectElement.parentElement.querySelector('.field-value');
        const operator = selectElement.value;

        if (operator === 'present' || operator === 'blank') {
            valueInput.style.display = 'none';
            valueInput.value = '';
        } else {
            valueInput.style.display = 'block';
        }
    }

    parseConditionUI(conditionElement) {
        const typeSelect = conditionElement.querySelector('.condition-type-select');
        const type = typeSelect.value;

        if (type === 'field') {
            // Field condition
            const field = conditionElement.querySelector('.field-path').value.trim();
            const op = conditionElement.querySelector('.operator-select').value;
            const value = conditionElement.querySelector('.field-value').value;

            const condition = { field, op };

            // Add value only if needed
            if (op !== 'present' && op !== 'blank') {
                // Try to parse as JSON for arrays/objects
                try {
                    condition.value = JSON.parse(value);
                } catch {
                    condition.value = value;
                }
            }

            return condition;
        } else {
            // Composite condition (all/any)
            const subContainer = conditionElement.querySelector('.subconditions-container');
            const subconditions = Array.from(subContainer.children).map(child =>
                this.parseConditionUI(child)
            );

            return { [type]: subconditions };
        }
    }

    saveRule() {
        // Validate inputs
        const ruleId = document.getElementById('ruleId').value.trim();
        const thenDecision = document.getElementById('thenDecision').value.trim();

        if (!ruleId) {
            alert('Rule ID is required');
            return;
        }

        if (!thenDecision) {
            alert('Decision is required');
            return;
        }

        // Parse condition
        const conditionBuilder = document.getElementById('conditionBuilder');
        const conditionElements = Array.from(conditionBuilder.children);

        if (conditionElements.length === 0) {
            alert('At least one condition is required');
            return;
        }

        const ifCondition = this.parseConditionUI(conditionElements[0]);

        // Build then clause
        const thenClause = {
            decision: thenDecision
        };

        const weight = parseFloat(document.getElementById('thenWeight').value);
        if (weight >= 0 && weight <= 1) {
            thenClause.weight = weight;
        }

        const reason = document.getElementById('thenReason').value.trim();
        if (reason) {
            thenClause.reason = reason;
        }

        // Create rule object
        const rule = {
            id: ruleId,
            if: ifCondition,
            then: thenClause
        };

        // Save or update
        if (this.currentRuleIndex !== null) {
            this.rules[this.currentRuleIndex] = rule;
        } else {
            this.rules.push(rule);
        }

        this.closeModal();
        this.renderRules();
        this.updateJSONPreview();
    }

    closeModal() {
        document.getElementById('ruleModal').classList.add('hidden');
        this.currentRule = null;
        this.currentRuleIndex = null;
    }

    renderRules() {
        const container = document.getElementById('rulesContainer');

        if (this.rules.length === 0) {
            container.innerHTML = '<p style="text-align: center; color: #6b7280; padding: 20px;">No rules yet. Click "Add Rule" to create one.</p>';
            return;
        }

        container.innerHTML = '';

        this.rules.forEach((rule, index) => {
            const ruleCard = document.createElement('div');
            ruleCard.className = 'rule-card';

            const conditionSummary = this.getConditionSummary(rule.if);

            ruleCard.innerHTML = `
                <div class="rule-header">
                    <span class="rule-id">${this.escapeHtml(rule.id)}</span>
                    <div class="rule-actions">
                        <button class="btn btn-sm btn-secondary edit-btn">Edit</button>
                        <button class="btn-remove delete-btn">×</button>
                    </div>
                </div>
                <div class="rule-summary">
                    IF: ${conditionSummary}<br>
                    THEN: ${this.escapeHtml(rule.then.decision)} (weight: ${rule.then.weight || 'default'})
                </div>
            `;

            ruleCard.querySelector('.edit-btn').addEventListener('click', () => this.openRuleModal(index));
            ruleCard.querySelector('.delete-btn').addEventListener('click', () => this.deleteRule(index));

            container.appendChild(ruleCard);
        });
    }

    getConditionSummary(condition) {
        if (condition.field) {
            const valueText = condition.value !== undefined ? ` "${this.escapeHtml(JSON.stringify(condition.value))}"` : '';
            return `${this.escapeHtml(condition.field)} ${condition.op}${valueText}`;
        } else if (condition.all) {
            return `ALL (${condition.all.length} conditions)`;
        } else if (condition.any) {
            return `ANY (${condition.any.length} conditions)`;
        }
        return 'unknown';
    }

    deleteRule(index) {
        if (confirm('Are you sure you want to delete this rule?')) {
            this.rules.splice(index, 1);
            this.renderRules();
            this.updateJSONPreview();
        }
    }

    updateJSONPreview() {
        const version = document.getElementById('rulesetVersion').value || '1.0';
        const ruleset = document.getElementById('rulesetName').value || 'my_ruleset';

        const output = {
            version: version,
            ruleset: ruleset,
            rules: this.rules
        };

        document.getElementById('jsonOutput').textContent = JSON.stringify(output, null, 2);
    }

    async validateRules() {
        const version = document.getElementById('rulesetVersion').value || '1.0';
        const ruleset = document.getElementById('rulesetName').value || 'my_ruleset';

        const payload = {
            version: version,
            ruleset: ruleset,
            rules: this.rules
        };

        try {
            const response = await fetch('/api/validate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(payload)
            });

            const result = await response.json();

            if (result.valid) {
                this.showValidationSuccess();
            } else {
                this.showValidationErrors(result.errors);
            }
        } catch (error) {
            console.error('Validation error:', error);
            this.showValidationErrors(['Network error: Could not connect to validation server']);
        }
    }

    showValidationSuccess() {
        const statusEl = document.getElementById('validationStatus');
        const errorsEl = document.getElementById('validationErrors');

        statusEl.className = 'validation-status success';
        statusEl.querySelector('.status-message').textContent = 'All rules are valid!';
        statusEl.classList.remove('hidden');

        errorsEl.classList.add('hidden');
    }

    showValidationErrors(errors) {
        const statusEl = document.getElementById('validationStatus');
        const errorsEl = document.getElementById('validationErrors');
        const errorList = document.getElementById('errorList');

        statusEl.className = 'validation-status error';
        statusEl.querySelector('.status-message').textContent = 'Validation failed. See errors below.';
        statusEl.classList.remove('hidden');

        errorList.innerHTML = '';
        errors.forEach(error => {
            const li = document.createElement('li');
            li.textContent = error;
            errorList.appendChild(li);
        });

        errorsEl.classList.remove('hidden');
    }

    clearAll() {
        if (confirm('Are you sure you want to clear all rules?')) {
            this.rules = [];
            this.renderRules();
            this.updateJSONPreview();
            document.getElementById('validationStatus').classList.add('hidden');
            document.getElementById('validationErrors').classList.add('hidden');
        }
    }

    copyJSON() {
        const jsonText = document.getElementById('jsonOutput').textContent;
        navigator.clipboard.writeText(jsonText).then(() => {
            const btn = document.getElementById('copyBtn');
            const originalText = btn.textContent;
            btn.textContent = '✓ Copied!';
            setTimeout(() => {
                btn.textContent = originalText;
            }, 2000);
        });
    }

    downloadJSON() {
        const jsonText = document.getElementById('jsonOutput').textContent;
        const blob = new Blob([jsonText], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `rules_${new Date().getTime()}.json`;
        a.click();
        URL.revokeObjectURL(url);
    }

    importJSON(event) {
        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                const data = JSON.parse(e.target.result);

                if (data.rules && Array.isArray(data.rules)) {
                    this.rules = data.rules;

                    if (data.version) {
                        document.getElementById('rulesetVersion').value = data.version;
                    }
                    if (data.ruleset) {
                        document.getElementById('rulesetName').value = data.ruleset;
                    }

                    this.renderRules();
                    this.updateJSONPreview();
                    alert('Rules imported successfully!');
                } else {
                    alert('Invalid JSON format. Expected "rules" array.');
                }
            } catch (error) {
                alert('Error parsing JSON: ' + error.message);
            }
        };
        reader.readAsText(file);

        // Reset input
        event.target.value = '';
    }

    loadExample() {
        const example = {
            version: '1.0',
            ruleset: 'example_approval_rules',
            rules: [
                {
                    id: 'high_priority_auto_approve',
                    if: {
                        all: [
                            { field: 'priority', op: 'eq', value: 'high' },
                            { field: 'user.role', op: 'eq', value: 'admin' }
                        ]
                    },
                    then: {
                        decision: 'approve',
                        weight: 0.95,
                        reason: 'High priority request from admin'
                    }
                },
                {
                    id: 'low_amount_approve',
                    if: {
                        all: [
                            { field: 'amount', op: 'lt', value: 1000 },
                            { field: 'status', op: 'eq', value: 'active' }
                        ]
                    },
                    then: {
                        decision: 'approve',
                        weight: 0.8,
                        reason: 'Low amount with active status'
                    }
                },
                {
                    id: 'missing_info_reject',
                    if: {
                        any: [
                            { field: 'description', op: 'blank' },
                            { field: 'assignee', op: 'blank' }
                        ]
                    },
                    then: {
                        decision: 'needs_info',
                        weight: 0.7,
                        reason: 'Missing required information'
                    }
                }
            ]
        };

        this.rules = example.rules;
        document.getElementById('rulesetVersion').value = example.version;
        document.getElementById('rulesetName').value = example.ruleset;

        this.renderRules();
        this.updateJSONPreview();
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = String(text);
        return div.innerHTML;
    }
}

// Initialize app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    window.ruleBuilder = new RuleBuilder();

    // Update JSON on metadata changes
    ['rulesetVersion', 'rulesetName'].forEach(id => {
        document.getElementById(id).addEventListener('input', () => {
            window.ruleBuilder.updateJSONPreview();
        });
    });
});
