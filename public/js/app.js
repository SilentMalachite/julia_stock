// Julia在庫管理システム - メインJavaScript

// DOMContentLoaded時の初期化
document.addEventListener('DOMContentLoaded', function() {
    // ツールチップの初期化
    initializeTooltips();
    
    // フォームバリデーション
    initializeFormValidation();
    
    // 削除確認ダイアログ
    initializeDeleteConfirmation();
    
    // テーブルソート
    initializeTableSort();
    
    // 検索フィルター
    initializeSearchFilter();
    
    // フラッシュメッセージの自動非表示
    initializeFlashMessages();
});

// ツールチップの初期化
function initializeTooltips() {
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });
}

// フォームバリデーション
function initializeFormValidation() {
    const forms = document.querySelectorAll('.needs-validation');
    Array.prototype.slice.call(forms).forEach(function (form) {
        form.addEventListener('submit', function (event) {
            if (!form.checkValidity()) {
                event.preventDefault();
                event.stopPropagation();
            }
            form.classList.add('was-validated');
        }, false);
    });
}

// 削除確認ダイアログ
function initializeDeleteConfirmation() {
    document.querySelectorAll('[data-confirm]').forEach(function(element) {
        element.addEventListener('click', function(e) {
            if (!confirm(this.getAttribute('data-confirm'))) {
                e.preventDefault();
                return false;
            }
        });
    });
}

// テーブルソート機能
function initializeTableSort() {
    const tables = document.querySelectorAll('.table-sortable');
    tables.forEach(table => {
        const headers = table.querySelectorAll('th[data-sort]');
        headers.forEach((header, index) => {
            header.style.cursor = 'pointer';
            header.addEventListener('click', () => sortTable(table, index));
        });
    });
}

function sortTable(table, columnIndex) {
    const tbody = table.querySelector('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));
    const isAscending = table.getAttribute('data-sort-order') !== 'asc';
    
    rows.sort((a, b) => {
        const aValue = a.cells[columnIndex].textContent.trim();
        const bValue = b.cells[columnIndex].textContent.trim();
        
        // 数値の場合は数値として比較
        if (!isNaN(aValue) && !isNaN(bValue)) {
            return isAscending ? 
                parseFloat(aValue) - parseFloat(bValue) : 
                parseFloat(bValue) - parseFloat(aValue);
        }
        
        // 文字列として比較
        return isAscending ? 
            aValue.localeCompare(bValue, 'ja') : 
            bValue.localeCompare(aValue, 'ja');
    });
    
    // ソート順を記録
    table.setAttribute('data-sort-order', isAscending ? 'asc' : 'desc');
    
    // DOMを更新
    rows.forEach(row => tbody.appendChild(row));
}

// 検索フィルター
function initializeSearchFilter() {
    const searchInput = document.getElementById('tableSearch');
    if (searchInput) {
        searchInput.addEventListener('keyup', function() {
            const filter = this.value.toLowerCase();
            const table = document.querySelector('.table-filterable');
            const rows = table.querySelectorAll('tbody tr');
            
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(filter) ? '' : 'none';
            });
        });
    }
}

// フラッシュメッセージの自動非表示
function initializeFlashMessages() {
    const alerts = document.querySelectorAll('.alert-dismissible');
    alerts.forEach(alert => {
        setTimeout(() => {
            const bsAlert = new bootstrap.Alert(alert);
            bsAlert.close();
        }, 5000);
    });
}

// 在庫数量の更新（Ajax）
function updateQuantity(stockId, newQuantity) {
    fetch(`/api/stocks/${stockId}`, {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({ quantity: newQuantity })
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showNotification('在庫数が更新されました', 'success');
            // UIを更新
            updateQuantityDisplay(stockId, newQuantity);
        } else {
            showNotification('更新に失敗しました', 'danger');
        }
    })
    .catch(error => {
        console.error('Error:', error);
        showNotification('エラーが発生しました', 'danger');
    });
}

// 通知表示
function showNotification(message, type = 'info') {
    const notification = document.createElement('div');
    notification.className = `alert alert-${type} alert-dismissible fade show position-fixed top-0 end-0 m-3`;
    notification.style.zIndex = '9999';
    notification.innerHTML = `
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.remove();
    }, 3000);
}

// 数量表示の更新
function updateQuantityDisplay(stockId, quantity) {
    const quantityElement = document.querySelector(`[data-stock-id="${stockId}"] .quantity`);
    if (quantityElement) {
        quantityElement.textContent = quantity;
        
        // 在庫状態に応じてクラスを更新
        const row = quantityElement.closest('tr');
        row.classList.remove('table-danger', 'table-warning');
        
        if (quantity === 0) {
            row.classList.add('table-danger');
        } else if (quantity < 10) {
            row.classList.add('table-warning');
        }
    }
}

// Excelファイルのドラッグ&ドロップ
function initializeFileDrop() {
    const dropZone = document.getElementById('excel-drop-zone');
    if (!dropZone) return;
    
    dropZone.addEventListener('dragover', (e) => {
        e.preventDefault();
        dropZone.classList.add('drag-over');
    });
    
    dropZone.addEventListener('dragleave', () => {
        dropZone.classList.remove('drag-over');
    });
    
    dropZone.addEventListener('drop', (e) => {
        e.preventDefault();
        dropZone.classList.remove('drag-over');
        
        const files = e.dataTransfer.files;
        if (files.length > 0 && files[0].name.endsWith('.xlsx')) {
            uploadExcelFile(files[0]);
        } else {
            showNotification('Excelファイル（.xlsx）を選択してください', 'warning');
        }
    });
}

// Excelファイルのアップロード
function uploadExcelFile(file) {
    const formData = new FormData();
    formData.append('file', file);
    
    fetch('/api/excel/import', {
        method: 'POST',
        body: formData
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showNotification(`${data.imported_count}件のデータをインポートしました`, 'success');
            setTimeout(() => {
                window.location.href = '/stocks';
            }, 2000);
        } else {
            showNotification('インポートに失敗しました: ' + data.error, 'danger');
        }
    })
    .catch(error => {
        console.error('Error:', error);
        showNotification('エラーが発生しました', 'danger');
    });
}

// グラフの初期化
function initializeCharts() {
    const chartElements = document.querySelectorAll('[data-chart]');
    chartElements.forEach(element => {
        const chartType = element.getAttribute('data-chart');
        const chartData = JSON.parse(element.getAttribute('data-chart-data'));
        
        new Chart(element, {
            type: chartType,
            data: chartData,
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom',
                    }
                }
            }
        });
    });
}

// ユーティリティ関数
const Utils = {
    // 日付フォーマット
    formatDate: function(date) {
        return new Intl.DateTimeFormat('ja-JP', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }).format(new Date(date));
    },
    
    // 通貨フォーマット
    formatCurrency: function(amount) {
        return new Intl.NumberFormat('ja-JP', {
            style: 'currency',
            currency: 'JPY'
        }).format(amount);
    },
    
    // 数値フォーマット
    formatNumber: function(number) {
        return new Intl.NumberFormat('ja-JP').format(number);
    }
};