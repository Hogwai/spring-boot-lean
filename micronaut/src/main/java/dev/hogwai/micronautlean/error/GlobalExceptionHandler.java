package dev.hogwai.micronautlean.error;

import io.micronaut.context.annotation.Requirements;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.Produces;
import io.micronaut.http.server.exceptions.ExceptionHandler;
import jakarta.inject.Singleton;

public class GlobalExceptionHandler {

    @Singleton
    @Produces
    static class NotFoundHandler implements ExceptionHandler<TransactionNotFoundException, HttpResponse<ErrorResponse>> {
        @Override
        public HttpResponse<ErrorResponse> handle(HttpRequest request, TransactionNotFoundException exception) {
            return HttpResponse.notFound(new ErrorResponse(exception.getMessage()));
        }
    }

    @Singleton
    @Produces
    static class BadRequestHandler implements ExceptionHandler<IllegalArgumentException, HttpResponse<ErrorResponse>> {
        @Override
        public HttpResponse<ErrorResponse> handle(HttpRequest request, IllegalArgumentException exception) {
            return HttpResponse.badRequest(new ErrorResponse(exception.getMessage()));
        }
    }

    @Singleton
    @Produces
    static class GenericHandler implements ExceptionHandler<Exception, HttpResponse<ErrorResponse>> {
        @Override
        public HttpResponse<ErrorResponse> handle(HttpRequest request, Exception exception) {
            // Ensure TransactionNotFound and IllegalArgument are not swallowed here; Micronaut picks most specific
            if (exception instanceof TransactionNotFoundException || exception instanceof IllegalArgumentException) {
                // delegate by rethrowing? fallback to specific code
                if (exception instanceof TransactionNotFoundException ex) {
                    return HttpResponse.status(io.micronaut.http.HttpStatus.NOT_FOUND)
                            .body(new ErrorResponse(ex.getMessage()));
                }
                return HttpResponse.badRequest(new ErrorResponse(exception.getMessage()));
            }
            return HttpResponse.serverError(new ErrorResponse("Internal error"));
        }
    }
}
