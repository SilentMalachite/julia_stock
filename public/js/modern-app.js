// モダンな在庫管理システムのJavaScript

class InventoryApp {
    constructor() {
        this.apiBaseUrl = '/api/v2';
        this.currentPage = 1;
        this.itemsPerPage = 20;
        this.searchTerm = '';
        this.selectedCategory = '';
        this.sortBy = 'updated_at';
        this.sortOrder = 'desc';
        this.init();
    }

    init() {
        this.bindEvents();
        this.loadStocks();
        this.initializeDataTable();
        this.setupRealTimeUpdates();
    }

    bindEvents() {
        // 検索機能
        const searchInput = document.getElementById('searchInput');
        if (searchInput) {
            searchInput.addEventListener('input', this.debounce((e) => {
                this.searchTerm = e.target.value;
                this.loadStocks();
            }, 300));
        }

        // カテゴリフィルター
        const categorySelect = document.getElementById('categoryFilter');
        if (categorySelect) {
            categorySelect.addEventListener('change', (e) => {
                this.selectedCategory = e.target.value;
                this.loadStocks();
            });
        }

        // 新規追加ボタン
        const addButton = document.getElementById('addStockBtn');
        if (addButton) {
            addButton.addEventListener('click', () => this.showAddModal());
        }

        // フォーム送信
        const stockForm = document.getElementById('stockForm');
        if (stockForm) {
            stockForm.addEventListener('submit', (e) => this.handleFormSubmit(e));
        }

        // Excel機能
        const importBtn = document.getElementById('importExcelBtn');
        if (importBtn) {
            importBtn.addEventListener('click', () => this.showImportModal());
        }

        const exportBtn = document.getElementById('exportExcelBtn');
        if (exportBtn) {
            exportBtn.addEventListener('click', () => this.exportToExcel());
        }
    }

    // データテーブルの初期化
    initializeDataTable() {
        const table = document.getElementById('stocksTable');
        if (table) {
            // ソート機能
            const headers = table.querySelectorAll('th[data-sortable]');
            headers.forEach(header => {
                header.style.cursor = 'pointer';
                header.addEventListener('click', () => {
                    const field = header.dataset.field;
                    if (this.sortBy === field) {
                        this.sortOrder = this.sortOrder === 'asc' ? 'desc' : 'asc';
                    } else {
                        this.sortBy = field;
                        this.sortOrder = 'asc';
                    }
                    this.loadStocks();
                });
            });
        }
    }

    // 在庫データの読み込み
    async loadStocks() {
        try {
            this.showLoading();
            
            const params = new URLSearchParams({
                page: this.currentPage,
                limit: this.itemsPerPage,
                search: this.searchTerm,
                category: this.selectedCategory,
                sortBy: this.sortBy,
                sortOrder: this.sortOrder
            });

            const response = await fetch(`${this.apiBaseUrl}/stocks?${params}`);
            const data = await response.json();

            this.renderStocks(data.stocks);
            this.renderPagination(data.totalPages);
            this.updateStatistics(data.statistics);
            
        } catch (error) {
            this.showError('在庫データの読み込みに失敗しました。');
            console.error('Error loading stocks:', error);
        } finally {
            this.hideLoading();
        }
    }

    // 在庫データの表示
    renderStocks(stocks) {
        const tbody = document.querySelector('#stocksTable tbody');
        if (!tbody) return;

        if (stocks.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="8" class="text-center py-4">
                        <i class="fas fa-box-open fa-3x text-muted mb-3"></i>
                        <p class="text-muted">在庫データがありません。</p>
                    </td>
                </tr>
            `;
            return;
        }

        tbody.innerHTML = stocks.map(stock => `
            <tr class="fade-in">
                <td>${this.escapeHtml(stock.product_code)}</td>
                <td>
                    <a href="#" class="text-decoration-none" onclick="app.showStockDetail(${stock.id})">
                        ${this.escapeHtml(stock.product_name)}
                    </a>
                </td>
                <td><span class="badge bg-secondary">${this.escapeHtml(stock.category)}</span></td>
                <td class="text-end">
                    ${this.formatQuantity(stock.quantity, stock.unit)}
                    ${this.getStockStatusBadge(stock.quantity)}
                </td>
                <td class="text-end">${this.formatCurrency(stock.price)}</td>
                <td>${this.escapeHtml(stock.location || '-')}</td>
                <td>${this.formatDateTime(stock.updated_at)}</td>
                <td class="text-center">
                    <div class="btn-group btn-group-sm">
                        <button class="btn btn-outline-primary" onclick="app.editStock(${stock.id})" title="編集">
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn btn-outline-danger" onclick="app.deleteStock(${stock.id})" title="削除">
                            <i class="fas fa-trash"></i>
                        </button>
                    </div>
                </td>
            </tr>
        `).join('');
    }

    // 在庫ステータスバッジ
    getStockStatusBadge(quantity) {
        if (quantity === 0) {
            return '<span class="badge bg-danger ms-2">在庫切れ</span>';
        } else if (quantity < 10) {
            return '<span class="badge bg-warning ms-2">低在庫</span>';
        }
        return '';
    }

    // ページネーション
    renderPagination(totalPages) {
        const pagination = document.getElementById('pagination');
        if (!pagination) return;

        let html = '';
        
        // 前へボタン
        html += `
            <li class="page-item ${this.currentPage === 1 ? 'disabled' : ''}">
                <a class="page-link" href="#" onclick="app.goToPage(${this.currentPage - 1})">
                    <i class="fas fa-chevron-left"></i>
                </a>
            </li>
        `;

        // ページ番号
        for (let i = 1; i <= totalPages; i++) {
            if (i === 1 || i === totalPages || (i >= this.currentPage - 2 && i <= this.currentPage + 2)) {
                html += `
                    <li class="page-item ${i === this.currentPage ? 'active' : ''}">
                        <a class="page-link" href="#" onclick="app.goToPage(${i})">${i}</a>
                    </li>
                `;
            } else if (i === this.currentPage - 3 || i === this.currentPage + 3) {
                html += '<li class="page-item disabled"><span class="page-link">...</span></li>';
            }
        }

        // 次へボタン
        html += `
            <li class="page-item ${this.currentPage === totalPages ? 'disabled' : ''}">
                <a class="page-link" href="#" onclick="app.goToPage(${this.currentPage + 1})">
                    <i class="fas fa-chevron-right"></i>
                </a>
            </li>
        `;

        pagination.innerHTML = html;
    }

    // ページ移動
    goToPage(page) {
        this.currentPage = page;
        this.loadStocks();
    }

    // 統計情報の更新
    updateStatistics(statistics) {
        if (statistics) {
            const updateElement = (id, value) => {
                const element = document.getElementById(id);
                if (element) element.textContent = value;
            };

            updateElement('totalItems', statistics.totalItems || 0);
            updateElement('totalValue', this.formatCurrency(statistics.totalValue || 0));
            updateElement('lowStockItems', statistics.lowStockItems || 0);
            updateElement('outOfStockItems', statistics.outOfStockItems || 0);
        }
    }

    // 新規追加モーダル表示
    showAddModal() {
        const modal = new bootstrap.Modal(document.getElementById('stockModal'));
        document.getElementById('modalTitle').textContent = '新規在庫登録';
        document.getElementById('stockForm').reset();
        document.getElementById('stockId').value = '';
        modal.show();
    }

    // 編集
    async editStock(id) {
        try {
            const response = await fetch(`${this.apiBaseUrl}/stocks/${id}`);
            const stock = await response.json();

            document.getElementById('modalTitle').textContent = '在庫編集';
            document.getElementById('stockId').value = stock.id;
            document.getElementById('productCode').value = stock.product_code;
            document.getElementById('productName').value = stock.product_name;
            document.getElementById('category').value = stock.category;
            document.getElementById('quantity').value = stock.quantity;
            document.getElementById('unit').value = stock.unit;
            document.getElementById('price').value = stock.price;
            document.getElementById('location').value = stock.location || '';
            document.getElementById('description').value = stock.description || '';

            const modal = new bootstrap.Modal(document.getElementById('stockModal'));
            modal.show();
        } catch (error) {
            this.showError('在庫データの取得に失敗しました。');
        }
    }

    // フォーム送信処理
    async handleFormSubmit(e) {
        e.preventDefault();
        
        const formData = new FormData(e.target);
        const stockId = formData.get('stockId');
        const data = {
            product_code: formData.get('productCode'),
            product_name: formData.get('productName'),
            category: formData.get('category'),
            quantity: parseInt(formData.get('quantity')),
            unit: formData.get('unit'),
            price: parseFloat(formData.get('price')),
            location: formData.get('location'),
            description: formData.get('description')
        };

        try {
            const url = stockId ? 
                `${this.apiBaseUrl}/stocks/${stockId}` : 
                `${this.apiBaseUrl}/stocks`;
            
            const method = stockId ? 'PUT' : 'POST';
            
            const response = await fetch(url, {
                method: method,
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(data)
            });

            if (response.ok) {
                this.showSuccess(stockId ? '在庫を更新しました。' : '在庫を登録しました。');
                bootstrap.Modal.getInstance(document.getElementById('stockModal')).hide();
                this.loadStocks();
            } else {
                throw new Error('Failed to save stock');
            }
        } catch (error) {
            this.showError('保存に失敗しました。');
        }
    }

    // 削除
    async deleteStock(id) {
        if (!confirm('本当に削除しますか？')) return;

        try {
            const response = await fetch(`${this.apiBaseUrl}/stocks/${id}`, {
                method: 'DELETE'
            });

            if (response.ok) {
                this.showSuccess('在庫を削除しました。');
                this.loadStocks();
            } else {
                throw new Error('Failed to delete stock');
            }
        } catch (error) {
            this.showError('削除に失敗しました。');
        }
    }

    // Excelエクスポート
    async exportToExcel() {
        try {
            const response = await fetch(`${this.apiBaseUrl}/excel/export`);
            const blob = await response.blob();
            
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `inventory_${new Date().toISOString().split('T')[0]}.xlsx`;
            document.body.appendChild(a);
            a.click();
            window.URL.revokeObjectURL(url);
            
            this.showSuccess('Excelファイルをダウンロードしました。');
        } catch (error) {
            this.showError('エクスポートに失敗しました。');
        }
    }

    // リアルタイム更新の設定
    setupRealTimeUpdates() {
        // WebSocketまたはポーリングでリアルタイム更新を実装
        setInterval(() => {
            this.loadStocks();
        }, 30000); // 30秒ごとに更新
    }

    // ユーティリティ関数
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }

    escapeHtml(text) {
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text ? text.replace(/[&<>"']/g, m => map[m]) : '';
    }

    formatQuantity(quantity, unit) {
        return `${quantity.toLocaleString()} ${unit}`;
    }

    formatCurrency(amount) {
        return new Intl.NumberFormat('ja-JP', {
            style: 'currency',
            currency: 'JPY'
        }).format(amount);
    }

    formatDateTime(dateString) {
        const date = new Date(dateString);
        return new Intl.DateTimeFormat('ja-JP', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }).format(date);
    }

    showLoading() {
        const spinner = document.getElementById('loadingSpinner');
        if (spinner) spinner.style.display = 'flex';
    }

    hideLoading() {
        const spinner = document.getElementById('loadingSpinner');
        if (spinner) spinner.style.display = 'none';
    }

    showSuccess(message) {
        this.showToast(message, 'success');
    }

    showError(message) {
        this.showToast(message, 'error');
    }

    showToast(message, type) {
        const toastContainer = document.getElementById('toastContainer');
        if (!toastContainer) return;

        const toast = document.createElement('div');
        toast.className = `toast toast-${type} show`;
        toast.innerHTML = `
            <div class="toast-header">
                <strong class="me-auto">${type === 'success' ? '成功' : 'エラー'}</strong>
                <button type="button" class="btn-close" data-bs-dismiss="toast"></button>
            </div>
            <div class="toast-body">${message}</div>
        `;

        toastContainer.appendChild(toast);

        setTimeout(() => {
            toast.remove();
        }, 5000);
    }
}

// アプリケーションの初期化
let app;
document.addEventListener('DOMContentLoaded', () => {
    app = new InventoryApp();
});