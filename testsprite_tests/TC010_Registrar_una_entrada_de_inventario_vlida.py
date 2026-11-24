import asyncio
import re
from playwright import async_api
from playwright.async_api import expect

async def run_test():
    pw = None
    browser = None
    context = None

    try:
        # Start a Playwright session in asynchronous mode
        pw = await async_api.async_playwright().start()

        # Launch a Chromium browser in headless mode with custom arguments
        browser = await pw.chromium.launch(
            headless=True,
            args=[
                "--window-size=1280,720",
                "--disable-dev-shm-usage",
                "--ipc=host",
                "--single-process"
            ],
        )

        # Create a new browser context (like an incognito window)
        context = await browser.new_context()
        # Wider default timeout to match the agent's DOM-stability budget;
        # auto-waiting Playwright APIs (expect, locator.wait_for) inherit this.
        context.set_default_timeout(15000)

        # Open a new page in the browser context
        page = await context.new_page()

        # Interact with the page elements to simulate user flow
        # -> navigate
        await page.goto("http://localhost:4200/")
        try:
            await page.wait_for_load_state("domcontentloaded", timeout=5000)
        except Exception:
            pass
        
        # -> Abrir la ruta de inicio de sesión de AYNI y comprobar si muestra el formulario de acceso.
        await page.goto("http://localhost:4200/login")
        try:
            await page.wait_for_load_state("domcontentloaded", timeout=5000)
        except Exception:
            pass
        
        # -> Introducir las credenciales de la dirigenta y enviar el formulario «Entrar».
        # Ej.: dirigenta@ayni.org text field
        elem = page.get_by_role("textbox", name="Usuario o correo electrónico *")
        await elem.wait_for(state="visible", timeout=10000)
        await elem.fill("dirigenta@ayni.org")
        
        # -> Introducir las credenciales de la dirigenta y enviar el formulario «Entrar».
        # •••••••• password field
        elem = page.get_by_role("textbox", name="Contraseña *")
        await elem.wait_for(state="visible", timeout=10000)
        await elem.fill("Dirigenta1234!")
        
        # -> Introducir las credenciales de la dirigenta y enviar el formulario «Entrar».
        # Entrar button
        elem = page.get_by_role("button", name="Entrar")
        await elem.click(timeout=10000)
        
        # -> Abrir «Inventario PEPS» para revisar las entradas existentes y las opciones para agregar una entrada.
        # Inventario PEPS link
        elem = page.get_by_role("link", name="Inventario PEPS")
        await elem.click(timeout=10000)
        
        # -> Open “+ Registrar entrada” and review the inventory-entry form fields.
        # + Registrar entrada button
        elem = page.get_by_role("button", name="+ Registrar entrada")
        await elem.click(timeout=10000)
        
        # -> Registrar una entrada de 2 L de Aceite Vegetal con fecha de vencimiento y motivo, y comprobar su reflejo en el inventario PEPS.
        # entrada_cantidad number field
        elem = page.get_by_role("spinbutton", name="Cantidad *")
        await elem.wait_for(state="visible", timeout=10000)
        await elem.fill("2")
        
        # -> Registrar una entrada de 2 L de Aceite Vegetal con fecha de vencimiento y motivo, y comprobar su reflejo en el inventario PEPS.
        # entrada_vencimiento date field
        elem = page.get_by_role("textbox", name="Fecha de vencimiento")
        await elem.wait_for(state="visible", timeout=10000)
        await elem.fill("2027-12-31")
        
        # -> Registrar una entrada de 2 L de Aceite Vegetal con fecha de vencimiento y motivo, y comprobar su reflejo en el inventario PEPS.
        # Ej.: Compra mensual text field
        elem = page.get_by_role("textbox", name="Motivo")
        await elem.wait_for(state="visible", timeout=10000)
        await elem.fill("Registro de prueba")
        
        # -> Registrar una entrada de 2 L de Aceite Vegetal con fecha de vencimiento y motivo, y comprobar su reflejo en el inventario PEPS.
        # Registrar entrada button
        elem = page.get_by_role("button", name="Registrar entrada", exact=True)
        await elem.click(timeout=10000)
        
        # -> Abrir «Lotes (orden PEPS)» y verificar que la nueva entrada de Aceite Vegetal esté visible.
        # Lotes (orden PEPS) button
        elem = page.get_by_role("button", name="Lotes (orden PEPS)")
        await elem.click(timeout=10000)
        
        # --> Assertions to verify final state
        
        # --> La entrada de Aceite Vegetal aparece en los lotes con el vencimiento registrado.
        # Assert-outcome: not verified — the export-time check could not be evaluated
        # Assert: Se muestra Aceite Vegetal en la lista de lotes.
        await expect(page.locator("tbody").nth(0)).to_contain_text("Aceite Vegetal", timeout=15000), "Se muestra Aceite Vegetal en la lista de lotes."
        # Assert-outcome: not verified — the export-time check could not be evaluated
        # Assert: El lote muestra el vencimiento registrado.
        await expect(page.locator("xpath=/html/body/app-root/app-panel-layout/div/div/main/app-inventario/div[4]/table/tbody/tr[8]/td[6]").nth(0)).to_have_text("31/12/2027", timeout=15000), "El lote muestra el vencimiento registrado."
        await asyncio.sleep(5)

    finally:
        if context:
            await context.close()
        if browser:
            await browser.close()
        if pw:
            await pw.stop()

asyncio.run(run_test())
    