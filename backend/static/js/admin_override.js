/**
 * Yekola Admin - Style Override via JS
 * Injecté après tous les CSS, donc imbattable.
 */
(function() {
  const css = `
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap');

    /* ── GLOBAL ── */
    *, body, .content-wrapper, .wrapper, .main-header, .main-sidebar, .card, .btn, table {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif !important;
    }

    /* ── BODY BACKGROUND ── */
    body.sidebar-mini .content-wrapper,
    body .content-wrapper {
      background: #F1F5F9 !important;
    }

    /* ── NAVBAR TOP ── */
    .main-header.navbar,
    nav.main-header.navbar {
      background: linear-gradient(135deg, #0D47A1 0%, #1976D2 100%) !important;
      border-bottom: none !important;
      box-shadow: 0 2px 16px rgba(13,71,161,0.25) !important;
    }
    .main-header .nav-link,
    .main-header .navbar-nav .nav-link,
    .main-header .navbar-nav .nav-item .nav-link {
      color: rgba(255,255,255,0.92) !important;
      font-weight: 500 !important;
    }
    .main-header .nav-link:hover {
      color: #fff !important;
    }

    /* ── SIDEBAR ── */
    .main-sidebar, aside.main-sidebar {
      background-color: #0F172A !important;
      box-shadow: 3px 0 24px rgba(0,0,0,0.18) !important;
    }
    .brand-link, .main-sidebar .brand-link {
      background: #060D1F !important;
      border-bottom: 1px solid rgba(255,255,255,0.06) !important;
      min-height: 56px !important;
    }
    .brand-text, .brand-link .brand-text {
      color: #fff !important;
      font-weight: 800 !important;
      font-size: 1.1rem !important;
      letter-spacing: -0.3px !important;
    }

    /* Sidebar nav items */
    .nav-sidebar > .nav-item > .nav-link {
      border-radius: 8px !important;
      margin: 2px 8px !important;
      color: #94A3B8 !important;
      font-size: 0.85rem !important;
      font-weight: 500 !important;
      transition: all 0.2s ease !important;
    }
    .nav-sidebar > .nav-item > .nav-link:hover {
      background: rgba(255,255,255,0.07) !important;
      color: #fff !important;
      padding-left: 18px !important;
    }
    .nav-sidebar > .nav-item > .nav-link.active,
    .nav-sidebar > .nav-item.menu-open > .nav-link {
      background: linear-gradient(90deg, #2563EB, #3B82F6) !important;
      color: #fff !important;
      box-shadow: 0 4px 14px rgba(37,99,235,0.35) !important;
    }
    .nav-sidebar .nav-icon {
      color: #475569 !important;
    }
    .nav-sidebar > .nav-item > .nav-link.active .nav-icon {
      color: #fff !important;
    }
    .nav-treeview .nav-link {
      color: #64748B !important;
      font-size: 0.82rem !important;
      padding-left: 36px !important;
      margin: 1px 8px !important;
      border-radius: 6px !important;
      transition: all 0.2s !important;
    }
    .nav-treeview .nav-link:hover {
      background: rgba(255,255,255,0.06) !important;
      color: #CBD5E1 !important;
    }
    .nav-treeview .nav-link.active {
      color: #60A5FA !important;
      background: rgba(59,130,246,0.12) !important;
    }

    /* ── CARDS ── */
    .card {
      border-radius: 14px !important;
      border: 1px solid #E2E8F0 !important;
      box-shadow: 0 4px 20px rgba(0,0,0,0.05) !important;
      overflow: hidden !important;
      margin-bottom: 20px !important;
      background: #fff !important;
    }
    .card-header {
      background: #FAFBFF !important;
      border-bottom: 1px solid #E2E8F0 !important;
      padding: 16px 20px !important;
      font-weight: 700 !important;
      font-size: 1rem !important;
      color: #0F172A !important;
    }
    .card-body {
      padding: 20px !important;
    }

    /* ── BUTTONS ── */
    .btn, input[type="submit"], button[type="submit"] {
      border-radius: 8px !important;
      font-weight: 600 !important;
      font-size: 0.85rem !important;
      padding: 8px 18px !important;
      transition: all 0.25s ease !important;
      border: none !important;
      letter-spacing: 0.1px !important;
    }
    .btn-primary, input[type="submit"] {
      background: linear-gradient(135deg, #2563EB, #1D4ED8) !important;
      color: #fff !important;
      box-shadow: 0 4px 14px rgba(37,99,235,0.28) !important;
    }
    .btn-primary:hover {
      transform: translateY(-2px) !important;
      box-shadow: 0 6px 20px rgba(37,99,235,0.4) !important;
    }
    .btn-success {
      background: linear-gradient(135deg, #10B981, #059669) !important;
      color: #fff !important;
      box-shadow: 0 4px 12px rgba(16,185,129,0.28) !important;
    }
    .btn-danger {
      background: linear-gradient(135deg, #EF4444, #DC2626) !important;
      color: #fff !important;
    }
    .btn-warning {
      background: linear-gradient(135deg, #F59E0B, #D97706) !important;
      color: #fff !important;
    }
    .btn-secondary, .btn-default {
      background: #F1F5F9 !important;
      color: #475569 !important;
      border: 1px solid #CBD5E1 !important;
    }
    .btn-info {
      background: linear-gradient(135deg, #0EA5E9, #0284C7) !important;
      color: #fff !important;
    }

    /* ── TABLES ── */
    #result_list thead th,
    table.table thead th {
      background: #F8FAFC !important;
      color: #64748B !important;
      font-size: 0.72rem !important;
      font-weight: 700 !important;
      text-transform: uppercase !important;
      letter-spacing: 0.8px !important;
      padding: 14px 16px !important;
      border-bottom: 2px solid #E2E8F0 !important;
    }
    #result_list thead th a,
    #result_list thead th a:visited {
      color: #64748B !important;
    }
    #result_list tbody td,
    table.table tbody td {
      padding: 13px 16px !important;
      color: #334155 !important;
      font-size: 0.875rem !important;
      border-bottom: 1px solid #F1F5F9 !important;
      vertical-align: middle !important;
    }
    #result_list tbody tr:hover td {
      background: #EFF6FF !important;
    }

    /* ── FORMS ── */
    .form-control, input[type="text"], input[type="email"], input[type="password"],
    input[type="number"], select, textarea {
      border-radius: 8px !important;
      border: 1.5px solid #CBD5E1 !important;
      padding: 9px 14px !important;
      font-size: 0.875rem !important;
      transition: all 0.2s !important;
      color: #0F172A !important;
      background: #fff !important;
    }
    .form-control:focus, input:focus, select:focus, textarea:focus {
      border-color: #2563EB !important;
      box-shadow: 0 0 0 3px rgba(37,99,235,0.12) !important;
      outline: none !important;
    }

    /* ── BREADCRUMB ── */
    .breadcrumb { background: transparent !important; padding: 0 !important; }
    .breadcrumb-item, .breadcrumb-item a { font-size: 0.8rem !important; color: #64748B !important; }

    /* ── CONTENT HEADER ── */
    .content-header h1 {
      font-size: 1.4rem !important;
      font-weight: 800 !important;
      color: #0F172A !important;
    }

    /* ── PAGINATION ── */
    .paginator .page-link, .pagination .page-link {
      border-radius: 8px !important;
      font-weight: 600 !important;
      color: #2563EB !important;
      margin: 0 2px !important;
    }
    .paginator .page-item.active .page-link,
    .pagination .page-item.active .page-link {
      background: #2563EB !important;
      color: #fff !important;
      border-color: #2563EB !important;
    }

    /* ── SMALL BOXES (dashboard) ── */
    .small-box {
      border-radius: 14px !important;
      box-shadow: 0 4px 20px rgba(0,0,0,0.08) !important;
      overflow: hidden !important;
    }
    .small-box h3 {
      font-weight: 800 !important;
      font-size: 2.2rem !important;
    }

    /* ── FOOTER ── */
    .main-footer {
      background: #fff !important;
      border-top: 1px solid #E2E8F0 !important;
      color: #64748B !important;
      font-size: 0.8rem !important;
    }

    /* ── ACTIONS BAR ── */
    .actions {
      background: #F8FAFC !important;
      border-radius: 8px !important;
      border: 1px solid #E2E8F0 !important;
      padding: 10px 14px !important;
    }
  `;

  const style = document.createElement('style');
  style.id = 'edurdc-admin-override';
  style.textContent = css;
  document.head.appendChild(style);

  console.log('[Yekola] ✅ Design Pro chargé.');
})();
