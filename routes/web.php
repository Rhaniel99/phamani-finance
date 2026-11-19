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
use App\Http\Controllers\ShareController;
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

    Route::get('transactions', [TransactionController::class, 'index'])->name('transactions.index');
    Route::post('transactions', [TransactionController::class, 'store'])->name('transactions.store');
    Route::put('transactions/{transaction}', [TransactionController::class, 'update'])->name('transactions.update');
    Route::delete('transactions/{transaction}', [TransactionController::class, 'destroy'])->name('transactions.destroy');
    Route::post('transactions/{transaction}/pay', [TransactionController::class, 'pay'])->name('transactions.pay');
    Route::delete('transactions/{transaction}/pay', [TransactionController::class, 'unpay'])->name('transactions.unpay');

    Route::post('recurring/{recurring}/end', [RecurringTransactionController::class, 'end'])->name('recurring.end');
    Route::post('recurring/{recurring}/auto-pay', [AutoPayController::class, 'recurring'])->name('recurring.auto-pay');
    Route::post('installments/{installment}/auto-pay', [AutoPayController::class, 'installment'])->name('installments.auto-pay');

    Route::post('accounts', [AccountController::class, 'store'])->name('accounts.store');
    Route::put('accounts/{account}', [AccountController::class, 'update'])->name('accounts.update');

    Route::get('cards/{account}', [CreditCardController::class, 'show'])->name('cards.show');
    Route::post('invoices/{invoice}/pay', [CreditCardController::class, 'pay'])->name('invoices.pay');
    Route::delete('invoices/{invoice}/payment', [CreditCardController::class, 'undo'])->name('invoices.undo');
    Route::post('categories', [CategoryController::class, 'store'])->name('categories.store');

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
