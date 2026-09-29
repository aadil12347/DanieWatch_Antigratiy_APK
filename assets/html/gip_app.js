document.addEventListener('DOMContentLoaded', () => {
    // 1. Mobile Navigation Toggle
    const toggleBtn = document.querySelector('.mobile-nav-toggle');
    const sidebar = document.querySelector('aside');
    
    if (toggleBtn && sidebar) {
        toggleBtn.addEventListener('click', () => {
            sidebar.classList.toggle('open');
            // Toggle hamburger icon to X
            const isOpen = sidebar.classList.contains('open');
            toggleBtn.innerHTML = isOpen 
                ? '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>'
                : '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h16"/></svg>';
        });
    }

    // Close sidebar on link click (mobile)
    const navLinks = document.querySelectorAll('.nav-links li a');
    navLinks.forEach(link => {
        link.addEventListener('click', () => {
            if (sidebar.classList.contains('open')) {
                sidebar.classList.remove('open');
                if (toggleBtn) {
                    toggleBtn.innerHTML = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h16"/></svg>';
                }
            }
        });
    });

    // 2. Scroll Spy: Highlight navigation based on current view
    const sections = document.querySelectorAll('section');
    const navItems = document.querySelectorAll('.nav-links li');

    window.addEventListener('scroll', () => {
        let current = '';
        sections.forEach(section => {
            const sectionTop = section.offsetTop;
            const sectionHeight = section.clientHeight;
            // Highlight a bit earlier for smoother transition
            if (pageYOffset >= (sectionTop - 180)) {
                current = section.getAttribute('id');
            }
        });

        navItems.forEach(li => {
            li.classList.remove('active');
            const href = li.querySelector('a').getAttribute('href').substring(1);
            if (href === current) {
                li.classList.add('active');
            }
        });
    });

    // 3. Interactive Checklists using LocalStorage
    const checklistItems = document.querySelectorAll('.checklist-item');
    
    checklistItems.forEach(item => {
        const checkbox = item.querySelector('input[type="checkbox"]');
        const listId = checkbox.getAttribute('id');
        
        // Load initial state
        const isCompleted = localStorage.getItem(`gip_check_${listId}`) === 'true';
        if (isCompleted) {
            checkbox.checked = true;
            item.classList.add('completed');
        }
        
        // Toggle on item click
        item.addEventListener('click', (e) => {
            // Prevent duplicate event if clicking the checkbox input directly
            if (e.target !== checkbox) {
                checkbox.checked = !checkbox.checked;
            }
            
            // Save state
            const checked = checkbox.checked;
            localStorage.setItem(`gip_check_${listId}`, checked);
            
            if (checked) {
                item.classList.add('completed');
            } else {
                item.classList.remove('completed');
            }
        });
    });
});
