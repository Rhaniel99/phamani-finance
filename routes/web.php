<?php

use App\Http\Controllers\AccountController;
use App\Http\Controllers\AutoPayController;
use App\Http\Controllers\Auth\GoogleAuthController;
use App\Http\Controllers\CategoryController;
use App\Http\Controllers\ContactController;
use App\Http\Controllers\CreditCardController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\InboxController;
use App\Http\Controllers\InvitationController;
use App\Http\Controllers\RecurringTransactionController;
use App\Http\Controllers\ReimbursementController;
use App\Http\Controllers\SettlementController;
use App\Http\Controllers\StatementImportController;
use App\Http\Controllers\ShareController;
use App\Http\Controllers\TagController;
use App\Http\Controllers\TransactionController;
use Illuminate\Support\Facades\Route;

/*
| Autenticação (somente Google)
*/
Route::middleware('guest')->group(function () {
    Route::get('/', [GoogleAuthController::class, 'login'])->name('login');

    Route::get('auth/google/redirect', [GoogleAuthController::class, 'redirect'])->name('auth.google.redirect');
    Route::get('auth/google/callback', [GoogleAuthController::class, 'callback'])->name('auth.google.callback');
});

Route::post('logout', [GoogleAuthController::class, 'logout'])
    ->middleware('auth')
    ->name('logout');

/*
| Aplicação
*/
Route::middleware('auth')->group(function () {
    Route::get('dashboard', DashboardController::class)->name('dashboard');

    // Compra para outra pessoa: "a receber"
    Route::post('receivables/{contact}/receive', [ReimbursementController::class, 'receive'])->name('receivables.receive');
    Route::delete('receivables/{split}', [ReimbursementController::class, 'undo'])->name('receivables.undo');

    // Acerto entre usuários: "paguei" (quem deve) → confirmar/recusar (quem recebe)
    Route::post('payables/{creditor}/pay', [SettlementController::class, 'pay'])->name('payables.pay');
    Route::post('settlements/{settlement}/confirm', [SettlementController::class, 'confirm'])->name('settlements.confirm');
    Route::post('settlements/{settlement}/reject', [SettlementController::class, 'reject'])->name('settlements.reject');
    Route::delete('settlements/{settlement}', [SettlementController::class, 'cancel'])->name('settlements.cancel');

    Route::get('transactions', [TransactionController::class, 'index'])->name('transactions.index');
    Route::post('transactions', [TransactionController::class, 'store'])->name('transactions.store');
    Route::put('transactions/{transaction}', [TransactionController::class, 'update'])->name('transactions.update');
    Route::delete('transactions/{transaction}', [TransactionController::class, 'destroy'])->name('transactions.destroy');
    Route::post('transactions/{transaction}/reconcile', [TransactionController::class, 'reconcile'])->name('transactions.reconcile');
    Route::post('transactions/{transaction}/pay', [TransactionController::class, 'pay'])->name('transactions.pay');
    Route::delete('transactions/{transaction}/pay', [TransactionController::class, 'unpay'])->name('transactions.unpay');

    Route::post('recurring/{recurring}/end', [RecurringTransactionController::class, 'end'])->name('recurring.end');
    Route::post('recurring/{recurring}/auto-pay', [AutoPayController::class, 'recurring'])->name('recurring.auto-pay');
    Route::post('installments/{installment}/auto-pay', [AutoPayController::class, 'installment'])->name('installments.auto-pay');

    Route::post('accounts', [AccountController::class, 'store'])->name('accounts.store');
    Route::put('accounts/{account}', [AccountController::class, 'update'])->name('accounts.update');

    Route::get('cards/{account}', [CreditCardController::class, 'show'])->name('cards.show');

    // Importar extrato do cartão (OCR)
    Route::post('cards/{account}/imports', [StatementImportController::class, 'store'])->name('imports.store');
    Route::get('imports/{import}', [StatementImportController::class, 'show'])->name('imports.show');
    Route::post('imports/{import}/accept', [StatementImportController::class, 'accept'])->name('imports.accept');
    Route::delete('imports/{import}', [StatementImportController::class, 'destroy'])->name('imports.destroy');

    Route::post('invoices/{invoice}/pay', [CreditCardController::class, 'pay'])->name('invoices.pay');
    Route::delete('invoices/{invoice}/payment', [CreditCardController::class, 'undo'])->name('invoices.undo');
    Route::post('categories', [CategoryController::class, 'store'])->name('categories.store');
    Route::put('categories/{category}', [CategoryController::class, 'update'])->name('categories.update');

    Route::put('tags/{tag}', [TagController::class, 'update'])->name('tags.update');
    Route::delete('tags/{tag}', [TagController::class, 'destroy'])->name('tags.destroy');

    Route::post('contacts', [ContactController::class, 'store'])->name('contacts.store');
    Route::put('contacts/{contact}', [ContactController::class, 'update'])->name('contacts.update');
    Route::delete('contacts/{contact}', [ContactController::class, 'destroy'])->name('contacts.destroy');
    Route::post('contacts/{contact}/invite', [InvitationController::class, 'store'])->name('contacts.invite');
    Route::post('contacts/{contact}/unlink', [InvitationController::class, 'unlink'])->name('contacts.unlink');

    // Pendências (convites e divisões compartilhadas)
    Route::get('inbox', [InboxController::class, 'index'])->name('inbox');
    Route::post('notifications/read', [InboxController::class, 'markNotificationsRead'])->name('notifications.read');
    Route::post('invitations/{invitation}/accept', [InvitationController::class, 'accept'])->name('invitations.accept');
    Route::post('invitations/{invitation}/decline', [InvitationController::class, 'decline'])->name('invitations.decline');
    Route::post('shares/{share}/accept', [ShareController::class, 'accept'])->name('shares.accept');
    Route::post('shares/{share}/decline', [ShareController::class, 'decline'])->name('shares.decline');
    Route::post('shares/{share}/leave', [ShareController::class, 'leave'])->name('shares.leave');
});
